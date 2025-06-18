#!/bin/bash

#To manage DNS records using cloudflare account DNS

if [ -f ".env" ]; then
    source .env
    source ipv6_utils.sh
    source docker_calls.sh
else
    echo "No env file, please create one in order to use your credentials"
    exit 1
fi

get_records() {
    if [ -z "$1" ]; then
        # No argument passed: Get all records
        records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
    else
        # Argument passed: Get a specific DNS record by ID
        local dns_record_id="$1"
        records=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$dns_record_id" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json")
    fi

    echo "$records"
}

update_record_address() {
	local record_id="$1"
	local new_content="$2"

	request=$(curl -X PATCH https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id \
	-H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
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

create_dns_record() {
    service_name="$1" # O mesmo nome do container

    read -p "Is your DNS record proxied by Cloudflare? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        proxied=true
    else
        proxied=false
    fi

    echo "Select a record type:"
    echo "1) A"
    echo "2) AAAA"
    echo "3) A & AAAA"
    echo "4) SRV"
    echo "5) CNAME"

    read -p "Enter choice (1 to 5): " choice

    case "$choice" in
        1) type="A"
           content=$(get_public_ipv4 "$service_name") ;;
        2) type="AAAA"
           content=$(get_public_ipv6 "$service_name") ;;
        3) # Criar registros A e AAAA separadamente
           # ipv4=$(get_public_ipv4 "$service_name") # doesnt make sense
           ipv6=$(get_public_ipv6 "$service_name")

           request_a=$(curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
               -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
               -H "Content-Type: application/json" \
               --data "$(jq -n \
                   --arg content "$PUBLIC_IPV4" \
                   --arg name "$service_name" \
                   --argjson proxied $proxied \
                   --arg type "A" \
                   '{content: $content, name: $name, proxied: $proxied, type: $type}')")

           request_aaaa=$(curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
               -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
               -H "Content-Type: application/json" \
               --data "$(jq -n \
                   --arg content "$ipv6" \
                   --arg name "$service_name" \
                   --argjson proxied $proxied \
                   --arg type "AAAA" \
                   '{content: $content, name: $name, proxied: $proxied, type: $type}')")

           echo "A Record Response: $request_a"
           echo "AAAA Record Response: $request_aaaa"
           return ;;
        4) type="SRV"
           read -p "Enter SRV service (e.g., _minecraft._tcp): " srv_service
           read -p "Enter SRV target domain (domain.com): " srv_target
           read -p "Enter SRV priority (default: 0): " srv_priority
           read -p "Enter SRV weight (default: 0): " srv_weight
           read -p "Enter SRV port: " srv_port

           request=$(curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
               -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
               -H "Content-Type: application/json" \
               --data "$(jq -n \
                   --argjson port $srv_port \
                   --argjson priority ${srv_priority:-0} \
                   --argjson weight ${srv_weight:-0} \
                   --arg target "$srv_target" \
                   --arg name "$service_name" \
                   --arg type "SRV" \
                   '{data: {port: $port, priority: $priority, weight: $weight, target: $target}, name: $name, type: $type}')")
           ;;
        5) type="CNAME"
           read -p "Enter CNAME target domain: " content
           request=$(curl -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
               -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
               -H "Content-Type: application/json" \
               --data "$(jq -n \
                   --arg content "$content" \
                   --arg name "$service_name" \
                   --argjson proxied $proxied \
                   --arg type "CNAME" \
                   '{content: $content, name: $name, proxied: $proxied, type: $type}')")
           ;;
        *) echo "Invalid choice. Defaulting to AAAA."
           type="AAAA"
           content=$(get_public_ipv6 "$service_name")
           ;;
    esac

    if [[ "$choice" -ne 3 && "$choice" -ne 5 ]]; then
        request=$(curl -X POST "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$(jq -n \
                --arg content "$content" \
                --arg name "$service_name" \
                --argjson proxied $proxied \
                --arg type "$type" \
                '{content: $content, name: $name, proxied: $proxied, type: $type}')")
        echo $request
    fi
}

update_container_records() {
    local container="$1"
    if declare -f "$2" > /dev/null; then
        local records="$2"
    else
        local folder_name=$(echo "$container" | cut -d'_' -f1)
        local records_ids_file="services/$container/records.json"

        jq -c '.[]' "$records_ids_file" | while read -r record; do
            record_id=$(echo "$record" | jq -r '.record_id')
            record_type=$(echo "$record" | jq -r '.type')
            record_name=$(echo "$record" | jq -r '.name')

            if [ "$container" == "$parsed_name" ]; then
                update_record_address "$id" "$content"
            fi
        done
    fi

    parse_records "$records" "$container"
}

update_all_records() {
    if watch_host_ip; then
        containers=$(get_containers)

        records=$(get_records)

        for container in $containers; do
            ipv6=$(get_public_ipv6 "$container")

            if watch_container_ip "$container" "$ipv6"; then
                update_container_records "$container" "$ipv6" "$records"
            fi
        done
    fi
}
