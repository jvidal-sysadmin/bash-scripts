#!/bin/bash

for i in `seq 1 10` ; do
 echo 'exit' | nc -w 3 $1 $2 ;
done
