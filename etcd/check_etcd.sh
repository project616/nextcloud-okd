#!/bin/bash
#
# Health check script for containerized ETCD cluster
#

LOGFILE=/tmp/etcd_state.log
ETCD_ENDPOINT="http://localhost:2379"
CLUSTERCHECK_FILE="/tmp/cluster_state.json"

# log helpers
function info() {
  echo "[INFO]: $1" >> $2
}
function warning() {
  echo "[WARNING]: $1" >> $2
}
function error() {
  echo "[ERROR]: $1" >> $2
}

# check command execution
function check_cmd() {
  info "Running $*..." $LOGFILE
  eval "$*"
  if [[ $? -ne 0 ]]; then
    error "Command execution failed." $LOGFILE
    return 1
  fi
  return 0
}

# check socket presence (OPEN & LISTENING)
function check_socket() {
  PORT=${1}
  SOCKET=$(ss -antopl|awk -v PORT=$PORT '$0 ~ PORT {print $4}'|wc -l)
  if [[ $SOCKET -eq 0 ]]; then
    error "Socket on port $PORT is either not open or is not in LISTEN state" $LOGFILE
    return 1
  fi
  info "Socket on port $PORT is OK (OPEN,LISTEN)" $LOGFILE
  return 0
}

# check cluster health
function cluster_health() {
  check_cmd curl -o $CLUSTERCHECK_FILE -L $ETCD_ENDPOINT/health 2>&1 > /dev/null
  if [[ $? -ne 0 ]]; then
    info "Checking cluster state..." $LOGFILE
    PYCMD="import json; exec('with open(\"$CLUSTERCHECK_FILE\") as ifile:\n\tx=json.load(ifile)\n\tprint x[\"healthy\"]')"
    ISHEALTHY=`python -c "$PYCMD"|awk '$0 ~ healthy {print $0}'|wc -l`
    if [[ $ISHEALTHY -ne 0 ]]; then
      info "Cluster is healthy" $LOGFILE
      [ -e $CLUSTERCHECK_FILE ] && rm $CLUSTERCHECK_FILE
      return 0
    else
      error "Cluster is unhealthy" $LOGFILE
      [ -e $CLUSTERCHECK_FILE ] && rm $CLUSTERCHECK_FILE
      return 1
    fi
  fi
  error "Cannot contact etcd endpoint at: $ETCD_ENDPOINT." $LOGFILE
  return 1
}

# readiness check
function readiness_probe() {
  # check etcd ports
  for port in 2379 2380
  do
    check_socket $port
    if [[ $? -ne 0 ]]; then
      error "Check port $port KO" $LOGFILE
      return 1
    fi
  done
  return 0
}

# liveliness check
function liveliness_probe() {
  cluster_health
  if [[ $? -ne 0 ]]; then
    info "Cluster health ok" $LOGFILE
    return 0
  else
    error "Cluster health ko" $LOGFILE
    return 1
  fi
}

# main
while getopts "rl" cmd
do
  case "${cmd}" in
    r)
      readiness_probe
      [[ $? -ne 0 ]] && exit 1
      exit 0
      ;;
    l)
      liveliness_probe
      [[ $? -ne 0 ]] && exit 1
      exit 0
      ;;
    *) 
      error "SYNTAX ERROR: use -l for liveliness probe and -r for readiness probe" $LOGFILE
      exit 1
      ;;
  esac
done

