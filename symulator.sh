#!/bin/bash
RANDOM=$$
for i in `seq 200`
do
x=0
RANGE=40
R=$(($(($RANDOM%$RANGE))+X))
echo $R
echo '{"vhost":"/","name":"amq.default","properties":{"delivery_mode":1,"headers":{}},"routing_key":"temperatura-kolejka","delivery_mode":"1","payload":"{\"temp\": '$R', \"timestamp\": \"'$(date)'\" }","headers":{},"props":{},"payload_encoding":"string"}' |
        curl --user pogodynka:tajnehaslo \
              -X POST -H 'content-type: application/json' \
                    --data-binary @-  \
                          'http://rabbitmq:15672/api/exchanges/%2F/amq.default/publish'
sleep 2

done