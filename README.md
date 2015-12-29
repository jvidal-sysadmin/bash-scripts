# bash-scripts

My bash scripts collection I use daily.

## amazon_get_prefixes.sh

Basicly, get amazon prefixes what you need parsing **REGION** and **SERVICE** using [JQ](https://stedolan.github.io/jq/).

Simple example:

```ShellSession
root@aux:~/jvidal-bash-scripts# ./amazon_get_prefixes.sh us-west-2 ROUTE53
"54.244.52.192/26"
"54.245.168.0/26"
```

Batch example:

```ShellSession
root@aux:~/jvidal-bash-scripts$ ./amazon_get_prefixes.sh us-west-2 ROUTE53 | while read LINE; do iptables -I INPUT -s "$LINE" -j DROP && echo "IP $LINE will be dropped now!"; done
IP 54.244.52.192/26 will be dropped now!
IP 54.245.168.0/26 will be dropped now!

root@aux:~/jvidal-bash-scripts$ iptables -L -v -n | grep 54.244.52.192
    0     0 DROP       all  --  *      *       54.244.52.192/26     0.0.0.0/0
```
