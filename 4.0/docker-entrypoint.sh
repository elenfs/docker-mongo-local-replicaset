#!/bin/bash
set -e

REPLICA_SET_NAME=${REPLICA_SET_NAME:=rs0}
USERNAME=${USERNAME:=dev}
PASSWORD=${PASSWORD:=dev}
PORT1=${PORT1:=27001}
PORT2=${PORT2:=27002}
PORT3=${PORT3:=27003}

function waitForMongo {
    port=$1
    n=0
    until [ $n -ge 20 ]
    do
        mongo admin --quiet --port $port --eval "db" && break
        n=$[$n+1]
        sleep 2
    done
}

if [ ! "$(ls -A /data/db1)" ]; then
    mkdir /data/db1
    mkdir /data/db2
    mkdir /data/db3
fi

echo "STARTING CLUSTER"

mongod --port $PORT3 --smallfiles --dbpath /data/db3 --replSet $REPLICA_SET_NAME --bind_ip=::,0.0.0.0 &
DB3_PID=$!
mongod --port $PORT2 --smallfiles --dbpath /data/db2 --replSet $REPLICA_SET_NAME --bind_ip=::,0.0.0.0 &
DB2_PID=$!
mongod --port $PORT1 --smallfiles --dbpath /data/db1 --replSet $REPLICA_SET_NAME --bind_ip=::,0.0.0.0 &
DB1_PID=$!

waitForMongo $PORT1
waitForMongo $PORT2
waitForMongo $PORT3

echo "CONFIGURING REPLICA SET"
CONFIG="{ _id: '$REPLICA_SET_NAME', members: [{_id: 0, host: 'localhost:$PORT1', priority: 2 }, { _id: 1, host: 'localhost:$PORT2' }, { _id: 2, host: 'localhost:$PORT3' } ]}"
mongo admin --port $PORT1 --eval "db.runCommand({ replSetInitiate: $CONFIG })"

waitForMongo $PORT2
waitForMongo $PORT3

mongo admin --port $PORT1 --eval "db.runCommand({ setParameter: 1, quiet: 1 })"
mongo admin --port $PORT2 --eval "db.runCommand({ setParameter: 1, quiet: 1 })"
mongo admin --port $PORT3 --eval "db.runCommand({ setParameter: 1, quiet: 1 })"

echo "REPLICA SET ONLINE"

trap 'echo "KILLING"; kill $DB1_PID $DB2_PID $DB3_PID; wait $DB1_PID; wait $DB2_PID; wait $DB3_PID' SIGINT SIGTERM EXIT

wait $DB1_PID
wait $DB2_PID
wait $DB3_PID
