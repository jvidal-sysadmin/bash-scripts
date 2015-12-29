#!/bin/bash
# SOURCE: http://docs.aws.amazon.com/general/latest/gr/aws-ip-ranges.html#aws-ip-download
#

# VARS
WHICH="/usr/bin/which"
AMAZON_JSON_LIST='https://ip-ranges.amazonaws.com/ip-ranges.json'
REGION="$1"
SERVICE="$2"
QUERY=".[] .\"prefixes\" | .[] | select(.region | contains(\"$REGION\")) | select(.service | contains(\"$SERVICE\")) | .ip_prefix"

# Check if JQ is installed
if [ ! $($WHICH jq) ]; then
	echo "jq is not installed, please install it to use the script."
	echo "This program is available in the mostly Linux distributions by official package."
fi

# Check arguments
if [ -z $REGION ] || [ -z $SERVICE ]; then
	echo "Usage: $0 <REGION> <SERVICE>"
	echo
	echo 'Region: The AWS region or GLOBAL for edge locations. Note that the CLOUDFRONT and ROUTE53 ranges are GLOBAL.'
	echo '	Valid values: ap-northeast-1 | ap-southeast-1 | ap-southeast-2 | cn-north-1 | eu-central-1 | eu-west-1 | sa-east-1 | us-east-1 | us-gov-west-1 | us-west-1 | us-west-2 | GLOBAL'
	echo
	echo 'Service: The subset of IP address ranges. Specify AMAZON to get all IP address ranges (for example, the ranges in the EC2 subset are also in the AMAZON subset). Note that some IP address ranges are only in the AMAZON subset.'
	echo '	Valid values: AMAZON | EC2 | CLOUDFRONT | ROUTE53 | ROUTE53_HEALTHCHECKS'
	exit 1
fi

# MAIN
curl -s -XGET "$AMAZON_JSON_LIST" | jq -s "$QUERY" | sed 's/"//g'
