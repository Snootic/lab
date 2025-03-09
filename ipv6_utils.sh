#!/bin/bash

# Functions to manage my Dynamic IPV6 addresses. My provider only gives me DHCPv6DP
# So my ipv6 changes every time the network changes.
# These functions will address the issue, managing the containers IPv6 in order to
# keep up with the external ipv6

get_public_ipv6() {
    # since some containers do not support ip -6 route command, we'll search in /proc/net/if_inet6
    # this way we can get the address, but still need to parse it
    local container="$1"

    docker exec -it $container sh -c 'awk "/eth0/ && !/fe80/ && !/fd00/ {print \$1}" /proc/net/if_inet6 | head -n 1'
}

parse_ipv6() {
    local raw_ip="$1"
    local ipv6=""

    # Split the ip into chunks of 4 characters and build the ipv6 string
    for ((i=0; i<${#raw_ip}; i+=4)); do
        ipv6="${ipv6}:${raw_ip:i:4}"
    done

    ipv6="${ipv6:1}"
    # for some very odd reason, calling it from update_dns_records did not remove the : at the end
    # but it does calling from bash...
    ipv6="${ipv6::-2}" # so I added this to trim the :, it works at least
    echo "$ipv6"
}

watch_container_ip() {
    local container="$1"
    local ipv6="$2"

    if ! docker exec -it $container test -f "/tmp/last_ipv6.txt"; then
        docker exec -it -e IPV6=$ipv6 $container sh -c "echo \"$IPV6\" > /tmp/last_ipv6.txt"
        echo "Previous IPV6 not found. Updating records anyway for $container"
        return 0
    fi

    local previous_ipv6=$(docker exec -it $container cat /tmp/last_ipv6.txt | tr -d '[:space:]')

    if [ "$ipv6" != "$previous_ipv6" ]; then
        echo "IPV6 changed, updating records for $container"
        docker exec -it -e IPV6=$ipv6 $container sh -c "echo \"$IPV6\" > /tmp/last_ipv6.txt"
        return 0
    else
        return 1
    fi
}

watch_host_ip() {
    local IP_FILE=/tmp/last_ipv6.txt
    local IPV6=$(ip -6 a | awk '/inet6/ && !/fe80/ && !/::1/ {print $2}' | cut -d/ -f1 | head -n 1)

    if [ ! -f "$IP_FILE" ]; then
        echo "$IPV6" > "$IP_FILE"
        return 0
    fi

    local previous_ipv6=$(cat "$IP_FILE")

    if [ "$IPV6" != "$previous_ipv6" ]; then
        echo "$IPV6" > "$IP_FILE"
        return 0
    else
        echo "IPV6 did not change, doing nothing"
        return 1
    fi
}
