#!/bin/bash
clear
my_ip=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
echo "."
echo "Local IP: https://$my_ip"
echo "."
# Set variables to be passed into the Docker compose file.
set -o allexport
. .env.open-webui
set +o allexport
echo "."
echo "Shutting Down Ollama & Open Web-UI Docker Services..."
echo "."
# Shutdown the docker compose stack
docker-compose -f ollama-stack.yml  down
sleep 2
docker container prune --force
echo "."
echo "."
echo "Ollama & Open Web-UI Shutdown Completed"
echo "."
echo "Local IP: https://$my_ip"
