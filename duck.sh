#!/bin/bash

if [ -f ".env" ]; then
    source .env
else
    echo "No env file, please create one in order to use your credentials"
    exit 1
fi

IPV4=$(curl 'https://api.ipify.org')
echo $IPV4
IPV6=$(ip -6 a | awk '/inet6/ && !/fe80/ && !/::1/ {print $2}' | cut -d/ -f1 | head -n 1)

echo url="https://www.duckdns.org/update?domains=$DUCKDNS_DOMAIN&token=$DUCK_TOKEN&ip=$IPV4&ipv6=$IPV6" | curl -k -o ~/duckdns/duck.log -K -
