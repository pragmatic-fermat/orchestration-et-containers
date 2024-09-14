#!/bin/bash
## Fait par SRN pour test

for d in $(doctl compute load-balancer list --format 'Name,ID' --no-header -o json | jq -r '.[] | "\(.name),\(.id)"' | egrep '^(a[0-9a-z]+|lb-groupe[0-9]+),' ); do
	echo "LB= $d"
	id=$(echo $d | cut -f2 -d',')
	echo "ID= $id"
	doctl compute load-balancer delete -f $id
done
