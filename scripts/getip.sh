#!/bin/bash
CMD='for i in {1..10}; do curl -s http://ip.me; done | sort | uniq -c' 

for NODE in $(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'); do
  echo "===== ${NODE} ====="
  kubectl run tmp-$RANDOM \
    --rm -q -it --restart=Never \
    --image nicolaka/netshoot \
    --overrides='{
      "apiVersion":"v1",
      "spec":{
        "nodeName":"'${NODE}'",
        "tolerations":[{"operator":"Exists"}]
      }
    }' \
    -- /bin/bash -c "$CMD"
done
