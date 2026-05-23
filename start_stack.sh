#!/bin/bash
STACK_NAME=ollama
docker stack deploy -c ollama-stack.yml --prune $STACK_NAME --detach=false 
sleep 4s
docker service ls
echo -e "\nLogin to the OLLAMA Web UI at http://127.0.0.1:8080/"
