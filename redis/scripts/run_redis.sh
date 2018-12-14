#!/bin/bash

ETCD_ENDPOINT="http://etcd.apps.fastcloud.it"
NAMESPACE="redis-cluster"
PORT=6379
CURL=$(which curl)
IFACE="eth0"
NODE_ID="$(uuidgen)"
NODE_NAME=""
ROLE="master"
LOG_TARGET="/tmp/redis_bootstrap"
CLUSTER=()


log() {
	msg=$1
	timestamp="$(date +%T)"
	function_caller="${FUNCNAME[1]}"
	echo "$timestamp" - "$function_caller" - "$msg" >> "$LOG_TARGET"
}


is_healthy() {
	echo "[ETCD] Is etcd healthy?"
	status=$("$CURL" -s "$ETCD_ENDPOINT"/health | jq 'select(.health == "true")')
	[ -n "$status" ] && return 0 || return 1
}

is_empty() {
	NM="$1"
	empty=$("$CURL" -s "$ETCD_ENDPOINT"/v2/keys/"$NM" | jq 'select(.errorCode == 100)')
	log "[ETCD] Check if namespace is empty => $empty"
	[ -n "$empty" ] && return 0 || return 1
}

register_node() {
	IPADDR=$(ip addr show "$IFACE" | sed -n '/inet /{s/^.*inet \([0-9.]\+\).*$/\1/;p}')
	#is_empty "$NAMESPACE"/"$ROLE"/"$NODE_NAME"
	#if [[ ! -z "$IPADDR" &&  "$(is_empty "$NAMESPACE"/"$ROLE"/"$NODE_NAME")" ]]; then
	log "[ETCD] Registering node ($NAMESPACE:{ $ROLE/$NODE_NAME:$IPADDR }) "
	result=$("$CURL" -s "$ETCD_ENDPOINT"/v2/keys/"$NAMESPACE"/$ROLE/"$NODE_NAME" -XPUT -d value="$IPADDR")
	#fi
	echo "$result"
}

join_cluster() {
	echo "TODO"
	redis-cli cluster meet "$MASTER" "$PORT"
}

usage() {
	echo "USAGE:"
	echo "$(basename "$0") [-n NAME] [-r ROLE]"
	echo "version: $VERSION"
	echo ""
	echo "-n: Name of the cluster node (POD on k8s)"
	echo "-r: Role of the node inside the cluster"
	echo "-h: Usage"
	echo "Examples: "
	echo "$(basename "$0") -h"
	echo "$(basename "$0") -n <REDIS_CLUSTER_NODE_XYZ> -r <MASTER/SLAVE>"
	exit 0
}

#####
#
#  JUST FOR ADMIN PURPOSES
#
####

reset_etcd_keys() {
	echo "[ETCD] Resetting etcd namespace $NAMESPACE"
	result=$("$CURL" -s \'"$ETCD_ENDPOINT"/v2/keys/$NAMESPACE?recursive=true\' -XDELETE)
	echo "$result"
}


####
# MAIN
####
main() {
	
	if [ "$#" -lt 2 ]; then
		echo "[ERR] Not enaugh parameters"
		exit 1
	fi

	while getopts ":n:r:" opt; do
		case "${opt}" in
			n) NODE_NAME=$2 ;;
			r) ROLE=$4 ;;
			*) usage ;;
		esac
	done

	echo "[DEBUG] Ready to run redis node ($NODE_NAME - $ROLE)"

	# First check the etcd health status
	is_healthy
	if [ "$?" -eq 1 ]; then
		echo "[ETCD] Health KO."
		exit 1
	fi
	echo "[ETCD] Health OK."
	
	register_node
	
	if [ -f /etc/redis/redis.conf ]; then
		echo "[RUN] redis-server /etc/redis/redis.conf"
		redis-server /etc/redis/redis.conf
	else
		echo "[ERR] Running base server with no config"
		redis-server
	fi
}

main "$@"
