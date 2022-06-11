RabbitMQ:
login: pogodynka
hasło: tajnehaslo

topic: ask-temp

PostgreSQL:
login: postgres
haslo: postgres


Jak uruchomić:

docker-compose up -d


rabbitmq: utworzenie kolejki
apt-get update
apt-get install curl
curl --user pogodynka:tajnehaslo \
      -X PUT -H 'content-type: application/json' \
      --data-binary '{"vhost":"/","name":"temperatura-kolejka","durable":"true","auto_delete":"false","arguments":{"x-queue-type":"classic"}}' \
      'http://localhost:15672/api/queues/%2F/temperatura-kolejka'



wysyłanie wiadomości z pogodynki-iot
(najpierw zainstalować curl)

echo '{"vhost":"/","name":"amq.default","properties":{"delivery_mode":1,"headers":{}},"routing_key":"temperatura-kolejka","delivery_mode":"1","payload":"{\"temp\": 1337, \"timestamp\": \"'$(date)'\" }","headers":{},"props":{},"payload_encoding":"string"}' |
curl --user pogodynka:tajnehaslo \
      -X POST -H 'content-type: application/json' \
      --data-binary @-  \
      'http://rabbitmq:15672/api/exchanges/%2F/amq.default/publish'


ustawienie kafka-connect-01:
curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/source-rabbitmq-00/config \
    -d '{
        "connector.class" : "io.confluent.connect.rabbitmq.RabbitMQSourceConnector",
        "kafka.topic" : "pogodynka-kafka",
        "rabbitmq.queue" : "temperatura-kolejka",
        "rabbitmq.username": "pogodynka",
        "rabbitmq.password": "tajnehaslo",
        "rabbitmq.host": "rabbitmq",
        "rabbitmq.port": "5672",
        "rabbitmq.virtual.host": "/",
        "confluent.license":"",
        "confluent.topic.bootstrap.servers":"kafka:29092",
        "confluent.topic.replication.factor":1,
        "value.converter": "org.apache.kafka.connect.converters.ByteArrayConverter",
        "key.converter": "org.apache.kafka.connect.storage.StringConverter"
    } '




podgląd wiadomości w kafka UI > topics > pogodynka-kafka > messages


w razie problemów test na rabbitMQ
 curl --silent --user pogodynka:tajnehaslo         -X POST -H 'content-type: application/json'         --data-binary '{"ackmode":"ack_requeue_true","encoding":"auto","count":"10"}'         'http://localhost:15672/api/queues/%2F/temperatura-kolejka/get'




ksql-cli:
ksql http://ksqldb-server:8088

i wewnątrz
można zweryfikować:
PRINT 'pogodynka-kafka' FROM BEGINNING;
(żeby wyjść trzeba nacisnąć ctrl+c)

trzeba ustawić schemat
CREATE STREAM inputdatastream (temp DOUBLE, timestamp VARCHAR) WITH (KAFKA_TOPIC='pogodynka-kafka', VALUE_FORMAT='JSON');
SET 'auto.offset.reset' = 'earliest';

Można sprawdzić czy poszło
SELECT temp, timestamp FROM inputdatastream EMIT CHANGES;


robimy nową tabelkę na podstawie starej - to jest niepotrzebne - feature jakby się udało policzyć średnią kroczącą przy pomocy SQL, jeżeli nie to można w kolejnym poleceniu zmienić 'topics' na inputdatastream
CREATE STREAM outputdatastream WITH (VALUE_FORMAT='AVRO') AS
  SELECT temp,
        timestamp
    FROM inputdatastream
   WHERE TIMESTAMP IS NOT NULL
    EMIT CHANGES;


describe outputdatastream - poakzuje typ

ustawienie kafka-connect-01:
do postgresql
  CREATE SINK CONNECTOR SINK_POSTGRES WITH (
    'connector.class'     = 'io.confluent.connect.jdbc.JdbcSinkConnector',
    'connection.url'      = 'jdbc:postgresql://postgres:5432/',
    'connection.user'     = 'postgres',
    'connection.password' = 'postgres',
    'topics'              = 'OUTPUTDATASTREAM',
    'key.converter'       = 'org.apache.kafka.connect.storage.StringConverter',
    'auto.create'         = 'true',
    'transforms'          = 'dropSysCols',
    'transforms.dropSysCols.type' = 'org.apache.kafka.connect.transforms.ReplaceField$Value',
    'transforms.dropSysCols.blacklist' = 'ROWKEY,ROWTIME'
  );




ustawienie kafka-connect-01:
do mongodb
curl -i -X PUT -H  "Content-Type:application/json" \
    http://localhost:8083/connectors/sink-mongodb-note-01/config \
    -d '{
    "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
    "topics":"OUTPUTDATASTREAM",
    "connection.uri":"mongodb://mongodb:27017",
    "database":"rmoff",
    "collection":"notes",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url":"http://schema-registry:8081"
    }'



mongodb:

mongo localhost:27017
use rmoff
db.notes.find()

