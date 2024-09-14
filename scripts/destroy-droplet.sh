#!/bin/bash


for d in $(doctl compute droplet list --format 'Name' | grep "soat-"); do
	echo $d
	doctl compute droplet delete -f $d
done
