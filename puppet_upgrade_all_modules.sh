#!/bin/bash
ENVIRONMENT="$1"

if [ -z $ENVIRONMENT ]; then
	ENVIRONMENT="production"
fi

WORKDIR="/etc/puppetlabs/code/environments"

cd "$WORKDIR/$ENVIRONMENT/modules"


for i in $(cat ./*/metadata.json | grep -v jvidal | jq -s '.[].name' | sed 's/"//g' | grep -v null); do
	puppet module upgrade $i
done
