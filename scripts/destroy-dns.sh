#!/bin/bash

for n in $(doctl compute domain records list soat.work | egrep "groupe[0-9]+" | cut -f1,2 -d' '); do
	echo "doctl compute domain records delete soat.work ${n} --force";
	doctl compute domain records delete soat.work ${n} --force;
done;
