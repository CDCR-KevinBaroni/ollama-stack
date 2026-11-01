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
echo "Remove ephemeral volumes before starting the stack..."
dv=($(docker volume ls --quiet))
for v in "${dv[@]}"; do
  if [[ $v != "insight-"** ]]; then
    # echo "Deleting volume: $v"
    docker volume rm $v
  fi
done
echo "."
# Start the stack
echo "Checking docker-compose version ..."
docker-compose --version
echo "."
echo "."
echo "Deploying Ollama & Open Web-UI Docker Services..."
echo "."
docker-compose -f ollama-stack.yml  up  --remove-orphans  -d 
echo "."
echo "Ollama & Open Web-UI Service Deployment Complete - Please wait until all services are started..."
echo "."
sleep 4s
# Status Docker services
echo "."
printf "If all services are not completely deployed, run the following command to check service status.\n"
echo docker ps
docker ps
echo "."
echo "Local IP: https://$my_ip"
echo -e "\n\nLogin to the Open Web-UI at http://$(hostname -I | awk '{print $1}'):8080/\n\n"

