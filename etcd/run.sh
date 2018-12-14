#!/bin/bash
#
# ETCD Startup script

NODE_PREFIX=${ETCD_NODE_PREFIX:-etcd-cluster-node}
NODE_INDEX=${ETCD_NODE_INDEX:-0}
INITIAL_CLUSTER_STATE=${CLUSTER_STATE:-new}
DATA_DIR=${ETCD_DATA_DIR:-/var/lib/etcd}
CLIENT_PORT=${ETCD_CLIENT_PORT:-2379}
SERVER_PORT=${ETCD_SERVER_PORT:-2380}

# check data dir
function cluster_needs_init() {
  DIR_CONTENTS=`ls -lart $DATA_DIR|wc -l`
  # if needed, patch the initial cluster state variable
  [[ $DIR_CONTENTS -gt 3 ]] && INITIAL_CLUSTER_STATE="existing"
}

cluster_needs_init

# startup server...
/usr/bin/etcd --name $NODE_PREFIX-$NODE_INDEX\
  --initial-advertise-peer-urls http://$NODE_PREFIX-$NODE_INDEX-svc:$SERVER_PORT\
  --listen-peer-urls http://0.0.0.0:$SERVER_PORT --listen-client-urls http://0.0.0.0:$CLIENT_PORT\
  --advertise-client-urls http://$NODE_PREFIX-$NODE_INDEX-svc:$CLIENT_PORT\
  --initial-cluster-state $INITIAL_CLUSTER_STATE \
  --data-dir $DATA_DIR\
  --initial-cluster-token "b02b8ebd1274266cb074f7e4ae9791d876817362" \
  --initial-cluster $NODE_PREFIX-0=http://$NODE_PREFIX-0-svc:$SERVER_PORT,$NODE_PREFIX-1=http://$NODE_PREFIX-1-svc:$SERVER_PORT,$NODE_PREFIX-2=http://$NODE_PREFIX-2-svc:$SERVER_PORT

#
