#!/bin/bash
source .env

check_lab_network() {
    if docker network ls --format "{{.Name}}" | grep -q "^lab$"; then
        return 0
    else
        return 1
    fi
}

create_lab_network() {
    docker network create -d macvlan \
        --ipv6 --subnet=$IPV6_SUBNET --gateway=$IPV6_GATEWAY \
        --subnet=$IPV4_SUBNET --gateway $IPV4_GATEWAY --ip-range $IPV4_RANGE \
        -o parent=$INTERFACE lab
}

get_containers() {
    docker container ps --format "{{.Names}}"
}