#!/bin/bash

if [ -f ".env" ]; then
    source .env
else
    echo "No env file, please create one in order to use your credentials"
    exit 1
fi

IP_FILE="/tmp/last_ipv6.txt"

IPV6=$(ip -6 a | awk '/inet6/ && !/fe80/ && !/::1/ {print $2}' | cut -d/ -f1 | head -n 1)

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
	echo "$records" | jq -c '.result[]' | while read -r item; do
    		id=$(echo "$item" | jq -r '.id')
    		type=$(echo "$item" | jq -r '.type')

    	case $type in
		#A) content=$IPV4 ;; # since I don't have a public IPV4 address, will be using ipv6 only. Maybe using a cloudflared tunnel can fix my problem.
		AAAA) content=$IPV6 ;;
		*) continue ;;
    	esac

    	update_record_address "$id" "$content"
	done
}

watch_ip() {
    if [ ! -f "$IP_FILE" ]; then
        echo "$IPV6" > "$IP_FILE"
        echo "Previous IPV6 not found. Updating records anyway for $IPV6"
        return 0
    fi

    local previous_ipv6=$(cat "$IP_FILE")

    if [ "$IPV6" != "$previous_ipv6" ]; then
        echo "IPV6 changed, updating records"
        echo "$IPV6" > "$IP_FILE"
        return 0
    else
        echo "IPV6 did not change, doing nothing"
        return 1
    fi
}


# main script

if watch_ip; then
    records=$(get_records)

    parse_records "$records"
else
    echo "No changes made"
fi
