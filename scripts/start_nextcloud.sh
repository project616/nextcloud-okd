#!/bin/bash

#######################################################################
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
#    author: fmount <fmount9@inventati.org>
#    version: 1.0
#    organization: Project616
#
########################################################################

CURL=$(which curl)
GREP=$(which grep)
PHP_FPM=$(which php-fpm)
APACHE2=$(which apache2-foreground)
SH=$(which sh)
MODE="apache"

SWIFT=$(which swift)
SWIFT_CONTAINER="plugins"

TAR="$(which tar)"
TAR_OPTIONS="xzvf"
PHP="$(which php)"
TAR_EXT=".tar.gz"

declare -A META
META=(
    [ETCD_ENDPOINT]="${ETCD:-"http://<ETCD_ENDPOINT>"}"
    [CONFIG_FILE]="${TARGET_FILE:-"/var/www/html/config/config.php"}"
    [NAMESPACE]="${ROOT_NODE:-"nextcloud"}"
    [ENTRYPOINT]="${ENTRY:-"/entrypoint.sh"}"
    [WORKDIR]="${WORK:-"/var/www/html"}"
    [SWIFTRC]="${SWIFTR:-"/usr/share/swiftrc"}"
    )

DEBUG=1
VERSION="v1"

# Fix on the starting scripts related to the
# CVE-2017-1002102: Basically the most elegant
# solution is to mount the configmap readonly and
# then copy the config.php in the $TARGET dir and
# continue the normal execution of the script ..
CVE-2017-1002102() {
    echo "Copying config.php to ${META[CONFIG_FILE]}"
    cp /usr/share/mycloud-config/config.php "${META[CONFIG_FILE]}"
    #echo $(ls ${META[CONFIG_FILE]})
}

log() {
        msg=$1
        timestamp="$(date +%T)"
        function_caller="${FUNCNAME[1]}"
        echo "$timestamp" - "$function_caller" - "$msg" >> "$LOG_TARGET"
}

etcd_is_dir() {
    KEY=$1
    CODE=$("$CURL" -s -L "${META[ETCD_ENDPOINT]}"/v2/keys/"$KEY" | jq '.node | .dir')
    [ "$CODE" == "true" ] && return 0 || return 1
}

is_attribute() {
    R=$(echo "$1" | sed s'/^"\(.*\)"$/\1/' | xargs -n 1 basename)
    J2_REGEX="\{\{ $R \}\}"
    echo "[GREP] Check regex: $J2_REGEX"
    [[ -n $($GREP -E "$J2_REGEX" "${META[CONFIG_FILE]}") ]] &&  return 0  || return 1
}

get_value() {
    KEY=$1
    echo "$("$CURL" -s -L "${META[ETCD_ENDPOINT]}"/v2/keys"$KEY" | jq '.node | .value')"
}

patch() {
    R=$(echo "$1" | sed s'/^"\(.*\)"$/\1/' | xargs -n 1 basename)
    VALUE=$2
    J2_REGEX="{{ $R }}"
    sed -i "s|$J2_REGEX|$VALUE|" "${META[CONFIG_FILE]}"
}

enable_plugin() {
    current_plugin=$1
    pl=$("$PHP" -f /var/www/html/occ app:list | grep "$current_plugin")
    if [ -n "$pl" ]; then
        echo "[PLUGIN] Enabling plugin: $current_plugin"
        "$PHP" -f /var/www/html/occ app:enable "$current_plugin"
    else
        echo "[PLUGIN] WARNING: Cannot enable plugin: $current_plugin"
    fi
}


build_plugins() {
    echo "[PLUGIN] Using swift ENV: ${META[SWIFTRC]}/keystonerc_swift"
    source "${META[SWIFTRC]}"/keystonerc_swift

    for item in $($SWIFT list $SWIFT_CONTAINER); do
        "$SWIFT" download "$SWIFT_CONTAINER" "$item"
        echo "[PLUGIN] Selected workdir: ${META[WORKDIR]}/apps"
        [ ! -d ${META[WORKDIR]}/apps/$(basename "$item" $TAR_EXT) ] && mkdir -p ${META[WORKDIR]}/apps/$(basename "$item" $TAR_EXT)
        1>/dev/null "$TAR" "$TAR_OPTIONS" "$item" -C "${META[WORKDIR]}/apps/$(basename "$item" $TAR_EXT)"
        echo "[PLUGIN] $item extracted ..."
        #rm -f "$item"
        enable_plugin "$(basename "$item" $TAR_EXT)"
    done
}

retrieve_parameters() {

    NAMESPACE=$1
    echo "[ETCD:Node] Getting nextcloud basic config from namespace key => $NAMESPACE/"
    result=$("$CURL" -s -L "${META[ETCD_ENDPOINT]}"/v2/keys/"$NAMESPACE" | jq '.node | .nodes[] | .key')
    #AB=()
    for key in $result; do
        key=$(echo "$key" |  sed 's/^"\(.*\)"$/\1/')
        if ! etcd_is_dir "$key"; then #&& is_attribute "$key"; then
            if is_attribute "$key"; then
                val=$(get_value "$key")
                val=$(echo "$val" | tr -d "\"")
                echo "[ETCD:$key] => Patching ${META[CONFIG_FILE]} with value $val"
                patch "$key" "$val"
            fi
        else
            # Use recursion here (eliminating the AB array)
            # if you want to use the deep first node selection
            #retrieve_parameters "$key"
            #AB+=("$key")
            retrieve_parameters "$key"
        fi
    done
    #for item in "${AB[@]}"; do
    #   retrieve_parameters "$item"
    #done
}

usage() {
    echo "USAGE:"
    echo "$(basename "$0") [ -r NAMESPACE ] [ -o CONFIG_FILE ]"
    echo "version: $VERSION"
    echo ""
    echo "-r: Root Node of the etcd endpoint"
    echo "-o: Config.php file to use for the running instance"
    echo "-h: Usage"
    echo "Examples: "
    echo "$(basename "$0") -h"
    echo "$(basename "$0") -r <NAMESPACE> -o <CONFIG_FILE>"
    exit 0
}


main() {

    if [ "$#" -lt 2 ]; then
        echo "[WARN] Not enaugh parameters"
        echo "[WARN] Using default namespace: ${META[NAMESPACE]}"
        echo "[WARN] Using default config file: ${META[CONFIG_FILE]}"
        echo "[WARN] Using default entrypoint: ${META[ENTRYPOINT]}"
        echo "[WARN] Using etcd endpoint: ${META[ETCD_ENDPOINT]}"
    fi

    while getopts ":n:o" opt; do
        case "${opt}" in

            n) META[NAMESPACE]=$1 ;;
            o) META[CONFIG_FILE]=$2 ;;
            *) usage ;;
        esac
    done


    CVE-2017-1002102
    if [ -f "${META[CONFIG_FILE]}" ]; then

        run_nextcloud

        #IFDEF_DEBUG
        if [ $DEBUG -eq 1 ]; then
            echo "[NXCONF] Using the following configuration ..."
            cat "${META[CONFIG_FILE]}"
        fi
        #ENDIF

        run_syslog
        build_plugins

        case "$MODE" in
        "apache") run_apache ;;
        "fpm") run_fpm ;;
        esac

    else
        echo "[ERR] Cannot find config file ${META[CONFIG_FILE]}"
        exit 1
    fi
}

run_syslog() {
    echo "[NX] Run rsyslog"
    service rsyslog start
}

run_apache() {
    echo "[NX] Run apache2-foreground"
    $APACHE2
}

run_fpm() {
    echo "[NX] Run fpm process"
    $PHP_FPM
}

run_nextcloud() {
    retrieve_parameters "${META[NAMESPACE]}"
    if [ -f "${META[ENTRYPOINT]}" ]; then
        "$SH" "${META[ENTRYPOINT]}"
    fi
}

main "$@"
