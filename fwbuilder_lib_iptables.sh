#!/bin/sh 
#


FWBDEBUG=""

PATH="/sbin:/usr/sbin:/bin:/usr/bin:${PATH}"
export PATH



LSMOD="lsmod"
MODPROBE="modprobe"
IPTABLES="iptables"
IP6TABLES="ip6tables"
IPTABLES_RESTORE="iptables-restore"
IP6TABLES_RESTORE="ip6tables-restore"
IP="ip"
IFCONFIG="ifconfig"
VCONFIG="vconfig"
BRCTL="brctl"
IFENSLAVE="ifenslave"
IPSET="ipset"
LOGGER="logger"

log() {
    echo "$1"
    which "$LOGGER" >/dev/null 2>&1 && $LOGGER -p info "$1"
}

getInterfaceVarName() {
    echo $1 | sed 's/\./_/'
}

getaddr_internal() {
    dev=$1
    name=$2
    af=$3
    L=$($IP $af addr show dev $dev |  sed -n '/inet/{s!.*inet6* !!;s!/.*!!p}' | sed 's/peer.*//')
    test -z "$L" && { 
        eval "$name=''"
        return
    }
    eval "${name}_list=\"$L\"" 
}

getnet_internal() {
    dev=$1
    name=$2
    af=$3
    L=$($IP route list proto kernel | grep $dev | grep -v default |  sed 's! .*$!!')
    test -z "$L" && { 
        eval "$name=''"
        return
    }
    eval "${name}_list=\"$L\"" 
}


getaddr() {
    getaddr_internal $1 $2 "-4"
}

getaddr6() {
    getaddr_internal $1 $2 "-6"
}

getnet() {
    getnet_internal $1 $2 "-4"
}

getnet6() {
    getnet_internal $1 $2 "-6"
}

# function getinterfaces is used to process wildcard interfaces
getinterfaces() {
    NAME=$1
    $IP link show | grep ": $NAME" | while read L; do
        OIFS=$IFS
        IFS=" :"
        set $L
        IFS=$OIFS
        echo $2
    done
}

diff_intf() {
    func=$1
    list1=$2
    list2=$3
    cmd=$4
    for intf in $list1
    do
        echo $list2 | grep -q $intf || {
        # $vlan is absent in list 2
            $func $intf $cmd
        }
    done
}

find_program() {
  PGM=$1
  which $PGM >/dev/null 2>&1 || {
    echo "\"$PGM\" not found"
    exit 1
  }
}
check_tools() {
  find_program which
  find_program $IPTABLES 
  find_program $MODPROBE 
  find_program $IP 
}
reset_iptables_v4() {
  $IPTABLES -P OUTPUT  DROP
  $IPTABLES -P INPUT   DROP
  $IPTABLES -P FORWARD DROP

cat /proc/net/ip_tables_names | while read table; do
  $IPTABLES -t $table -L -n | while read c chain rest; do
      if test "X$c" = "XChain" ; then
        $IPTABLES -t $table -F $chain
      fi
  done
  $IPTABLES -t $table -X
done
}

reset_iptables_v6() {
  $IP6TABLES -P OUTPUT  DROP
  $IP6TABLES -P INPUT   DROP
  $IP6TABLES -P FORWARD DROP

cat /proc/net/ip6_tables_names | while read table; do
  $IP6TABLES -t $table -L -n | while read c chain rest; do
      if test "X$c" = "XChain" ; then
        $IP6TABLES -t $table -F $chain
      fi
  done
  $IP6TABLES -t $table -X
done
}


P2P_INTERFACE_WARNING=""

missing_address() {
    address=$1
    cmd=$2

    oldIFS=$IFS
    IFS="@"
    set $address
    addr=$1
    interface=$2
    IFS=$oldIFS



    $IP addr show dev $interface | grep -q POINTOPOINT && {
        test -z "$P2P_INTERFACE_WARNING" && echo "Warning: Can not update address of interface $interface. fwbuilder can not manage addresses of point-to-point interfaces yet"
        P2P_INTERFACE_WARNING="yes"
        return
    }

    test "$cmd" = "add" && {
      echo "# Adding ip address: $interface $addr"
      echo $addr | grep -q ':' && {
          $FWBDEBUG $IP addr $cmd $addr dev $interface
      } || {
          $FWBDEBUG $IP addr $cmd $addr broadcast + dev $interface
      }
    }

    test "$cmd" = "del" && {
      echo "# Removing ip address: $interface $addr"
      $FWBDEBUG $IP addr $cmd $addr dev $interface || exit 1
    }

    $FWBDEBUG $IP link set $interface up
}

list_addresses_by_scope() {
    interface=$1
    scope=$2
    ignore_list=$3
    $IP addr ls dev $interface | \
      awk -v IGNORED="$ignore_list" -v SCOPE="$scope" \
        'BEGIN {
           split(IGNORED,ignored_arr);
           for (a in ignored_arr) {ignored_dict[ignored_arr[a]]=1;}
         }
         (/inet |inet6 / && $0 ~ SCOPE && !($2 in ignored_dict)) {print $2;}' | \
        while read addr; do
          echo "${addr}@$interface"
	done | sort
}


update_addresses_of_interface() {
    ignore_list=$2
    set $1 
    interface=$1 
    shift

    FWB_ADDRS=$(
      for addr in $*; do
        echo "${addr}@$interface"
      done | sort
    )

    CURRENT_ADDRS_ALL_SCOPES=""
    CURRENT_ADDRS_GLOBAL_SCOPE=""

    $IP link show dev $interface >/dev/null 2>&1 && {
      CURRENT_ADDRS_ALL_SCOPES=$(list_addresses_by_scope $interface 'scope .*' "$ignore_list")
      CURRENT_ADDRS_GLOBAL_SCOPE=$(list_addresses_by_scope $interface 'scope global' "$ignore_list")
    } || {
      echo "# Interface $interface does not exist"
      # Stop the script if we are not in test mode
      test -z "$FWBDEBUG" && exit 1
    }

    diff_intf missing_address "$FWB_ADDRS" "$CURRENT_ADDRS_ALL_SCOPES" add
    diff_intf missing_address "$CURRENT_ADDRS_GLOBAL_SCOPE" "$FWB_ADDRS" del
}

clear_addresses_except_known_interfaces() {
    $IP link show | sed 's/://g' | awk -v IGNORED="$*" \
        'BEGIN {
           split(IGNORED,ignored_arr);
           for (a in ignored_arr) {ignored_dict[ignored_arr[a]]=1;}
         }
         (/state/ && !($2 in ignored_dict)) {print $2;}' | \
         while read intf; do
            echo "# Removing addresses not configured in fwbuilder from interface $intf"
            $FWBDEBUG $IP addr flush dev $intf scope global
            $FWBDEBUG $IP link set $intf down
         done
}

check_file() {
    test -r "$2" || {
        echo "Can not find file $2 referenced by address table object $1"
        exit 1
    }
}

check_run_time_address_table_files() {
    :
    
}

load_modules() {
    :
    OPTS=$1
    MODULES_DIR="/lib/modules/`uname -r`/kernel/net/"
    MODULES=$(find $MODULES_DIR -name '*conntrack*' \! -name '*ipv6*'|sed  -e 's/^.*\///' -e 's/\([^\.]\)\..*/\1/')
    echo $OPTS | grep -q nat && {
        MODULES="$MODULES $(find $MODULES_DIR -name '*nat*'|sed  -e 's/^.*\///' -e 's/\([^\.]\)\..*/\1/')"
    }
    echo $OPTS | grep -q ipv6 && {
        MODULES="$MODULES $(find $MODULES_DIR -name nf_conntrack_ipv6|sed  -e 's/^.*\///' -e 's/\([^\.]\)\..*/\1/')"
    }
    for module in $MODULES; do 
        if $LSMOD | grep ${module} >/dev/null; then continue; fi
        $MODPROBE ${module} ||  exit 1 
    done
}

verify_interfaces() {
    :
    echo "Verifying interfaces: lo eth0"
    for i in lo eth0 ; do
        $IP link show "$i" > /dev/null 2>&1 || {
            log "Interface $i does not exist"
            exit 1
        }
    done
}

prolog_commands() {
    echo "Running prolog script"
    sp=22 ## port to secure
p1=88 ## port to touch first
p2=888 ## port to touch second
p3=8888 ## port to touch third
tot=10 ## time out in seconds

$IPTABLES -N kc
$IPTABLES -N kc1
$IPTABLES -N kc2

$IPTABLES -A INPUT -m state --state NEW -p tcp --dport $sp -m recent --rcheck --name portKnock --seconds $tot -j kc
$IPTABLES -A INPUT -m state --state NEW -p tcp --dport $p1 -m recent --name portKnock2 --set -j DROP
$IPTABLES -A INPUT -m state --state NEW -p tcp --dport $p2 -m recent --rcheck --name portKnock2 --seconds $tot -j kc1
$IPTABLES -A INPUT -m state --state NEW -p tcp --dport $p3 -m recent --rcheck --name portKnock1 --seconds $tot -j kc2

$IPTABLES -A kc -m recent --name portKnock --remove -j ACCEPT

$IPTABLES -A kc1 -m recent --name portKnock2 --remove
$IPTABLES -A kc1 -m recent --name portKnock1 --set -j DROP

$IPTABLES -A kc2 -m recent --name portKnock1 --remove
$IPTABLES -A kc2 -m recent --name portKnock --set -j DROP

$IPTABLES -A INPUT -m state --state NEW -m tcp -p tcp --dport $((p1 - 1)) -m recent --name portKnock2 --remove -j DROP
$IPTABLES -A INPUT -m state --state NEW -m tcp -p tcp --dport $((p1 + 1)) -m recent --name portKnock2 --remove -j DROP
$IPTABLES -A INPUT -m state --state NEW -m tcp -p tcp --dport $((p2 - 1)) -m recent --name portKnock1 --remove -j DROP
$IPTABLES -A INPUT -m state --state NEW -m tcp -p tcp --dport $((p2 + 1)) -m recent --name portKnock1 --remove -j DROP
$IPTABLES -A INPUT -m state --state NEW -m tcp -p tcp --dport $((p3 - 1)) -m recent --name portKnock --remove -j DROP
$IPTABLES -A INPUT -m state --state NEW -m tcp -p tcp --dport $((p3 + 1)) -m recent --name portKnock --remove -j DROP
}

epilog_commands() {
    echo "Running epilog script"
    
}

run_epilog_and_exit() {
    epilog_commands
    exit $1
}

configure_interfaces() {
    :
    # Configure interfaces
    # See http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=429689
    # this ensures that secondary ip address is "promoted" to primary
    # when primary address is deleted, instead of deleting both
    # primary and secondary addresses. It looks like this is only
    # available starting from Linux 2.6.16 
    test -f /proc/sys/net/ipv4/conf/all/promote_secondaries && \
        echo 1 >  /proc/sys/net/ipv4/conf/all/promote_secondaries
    update_addresses_of_interface "lo ::1/128 127.0.0.1/8" ""
    update_addresses_of_interface "eth0 2001:41d0:8:54c4::/64 37.59.1.196/24" ""
}

script_body() {
    echo 1 > /proc/sys/net/ipv4/conf/all/rp_filter 
    echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts 
}

ip_forward() {
    :
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

reset_all() {
    :
    reset_iptables_v4
  reset_iptables_v6
}

block_action() {
    reset_all
}

stop_action() {
    reset_all
    $IPTABLES -P OUTPUT  ACCEPT
    $IPTABLES -P INPUT   ACCEPT
    $IPTABLES -P FORWARD ACCEPT
    $IP6TABLES -P OUTPUT  ACCEPT
    $IP6TABLES -P INPUT   ACCEPT
    $IP6TABLES -P FORWARD ACCEPT
}

check_iptables() {
    IP_TABLES="$1"
    [ ! -e $IP_TABLES ] && return 151
    NF_TABLES=$(cat $IP_TABLES 2>/dev/null)
    [ -z "$NF_TABLES" ] && return 152
    return 0
}
status_action() {
    check_iptables "/proc/net/ip_tables_names"
    ret_ipv4=$?
    check_iptables "/proc/net/ip6_tables_names"
    ret_ipv6=$?
    [ $ret_ipv4 -eq 0 -o $ret_ipv6 -eq 0 ] && return 0
    [ $ret_ipv4 -eq 151 -o $ret_ipv6 -eq 151 ] && {
        echo "iptables modules are not loaded"
    }
    [ $ret_ipv4 -eq 152 -o $ret_ipv6 -eq 152 ] && {
        echo "Firewall is not configured"
    }
    exit 3
}
