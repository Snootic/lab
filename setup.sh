#!/bin/bash
source .env
source dns_records.sh

create_service() {
    read -p "Your service name: " service_name

    mkdir -p ./services/$service_name

    # Create the compose.yaml file with a default structure
    cat > ./services/$service_name/compose.yaml <<EOF
services:
  $service_name:
    container_name:$service_name
    image: $service_name:latest
    networks:
      - lab
networks:
  lab:
    external: true
EOF

    echo "Created compose.yaml with default structure"

    nano services/$service_name/compose.yaml

    read -p "Does this container have a Dockerfile? (y/n): " has_dockerfile
    if [[ "$has_dockerfile" =~ ^[Yy]$ ]]; then
        nano ./services/$service_name/Dockerfile
        echo "Created Dockerfile for the service."
    fi
    while true; do
        read -p "Enter the name of another file to create (or press Enter to skip): " file_name
        if [[ -z "$file_name" ]]; then
            break
        fi
        nano ./services/$service_name/$file_name
    done

    read -p "Do you want to setup a Cloudflare DNS record to your containers of this service? (y/n): " dns_record

    if [[ "$dns_record" =~ ^[Yy]$ ]]; then
        start "$service_name"

        if docker ps --filter "name=$service_name" --format "{{.ID}}" | grep -q .; then
            request=$(create_dns_record "$service_name")
            echo "$request"
        else
            echo "Error: Container $service_name did not start successfully. Skipping DNS record setup."
            echo "You can create it manually after by calling create_dns_record or going to your cloudflare dashboard"
        fi
    fi

    echo "Service setup completed."
}

start_all() {
    echo "Starting all services..."
    services=("pihole" "vaultwarden" "minecraft")

    for service in "${services[@]}"; do
        echo "Starting $service..."
        docker compose -f "services/$service/compose.yaml" up -d
    done

    echo "All services started!"
}

start() {
    if [ -z "$1" ]; then
        echo "Error: Need to provide a service name."
        exit 1
    fi

    service="$1"
    compose_file="services/$service/compose.yaml"

    if [ ! -f "$compose_file" ]; then
        echo "Error: Compose file '$compose_file' not found!"
        exit 1
    fi

    echo "Starting $service container..."

    docker compose -f "$compose_file" up -d
    if [ $? -ne 0 ]; then
        echo "Error: Failed to start container $service."
        exit 1
    fi

    sleep 2  # Give Docker some time to start the container

    container_id=$(docker ps --filter "name=$service" --format "{{.ID}}")
    if [ -z "$container_id" ]; then
        echo "Error: Container $service did not start successfully."
        docker compose -f "$compose_file" logs
        exit 1
    fi

    echo "Container $service started successfully! (ID: $container_id)"
}


if declare -f "$1" > /dev/null; then
    "$1" "${@:2}"
else
    echo "Error: Function '$1' not found."
    echo "Usage: $0 {create_service|start_all|start (service)}"
    exit 1
fi
