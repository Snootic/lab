#!/bin/bash

if [ -f ".env" ]; then
    source .env
    source ipv6_utils.sh
else
    echo "No env file, please create one in order to use your credentials"
    exit 1
fi

get_records() {
	records=$(curl -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
	-H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
	-H "Content-Type: application/json")

	echo $records
}

update_record_address() {
	# Ordering what each argument should be:
	local record_id="$1"
	local new_content="$2" #ip address

	request=$(curl -X PATCH https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$1 \
	-H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
	-H "Content-Type: application/json" \
	--data "$(jq -n --arg content "$new_content" '{"content":$content}')"
	)
	echo $request
}

parse_records() {
	local records="$1"
	local service_name="$2"
    local ipv6="$3"

    echo "$records" | jq -c '.result[]' | while read -r item; do
    		id=$(echo "$item" | jq -r '.id')
    		type=$(echo "$item" | jq -r '.type')
            name=$(echo "$item" | jq -r '.name')

    	case $type in
		    #A) content=$IPV4 ;; # since I don't have a public IPV4 address, will be using ipv6 only. Maybe using a cloudflared tunnel can fix my problem.
		    AAAA) content="$ipv6" ;;
		    *) continue ;;
    	esac

        local parsed_name=$(echo "$name" | awk -F'.' '{print $1}') 
        if [ "$service_name" == "$parsed_name" ]; then
            update_record_address "$id" "$content"
        fi
	done
}

get_containers() {
    docker container ps --format "{{.Names}}"
}

update_container_records() {
    local container="$1"
    local ipv6="$2"
    local records="$3"

    parse_records "$records" "$container" "$ipv6"
}

force_container_update() {
    local container="$1"
    local records=$(get_records)
    local raw_ip=$(get_public_ipv6 "$container")
    local ipv6=$(parse_ipv6 "$raw_ip")

    update_container_records "$container" "$ipv6" "$records"
}

if watch_host_ip; then
    containers=$(get_containers)

    records=$(get_records)

    for container in $containers; do
        raw_ip=$(get_public_ipv6 "$container")
        ipv6=$(parse_ipv6 "$raw_ip")

        if watch_container_ip "$container" "$ipv6"; then
            update_container_records "$container" "$ipv6" "$records"
        fi
    done
fi
