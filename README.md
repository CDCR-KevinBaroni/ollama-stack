# ollama-stack

1. Initialize Swarm (single node)
   docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')

#

$ docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
Swarm initialized: current node (yd2c8twdgqrsh5n1yzdj904cg) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-5fyphx7o9k6faz0bnif33oa7zuqzmej4feew4iiomz5kokzzg4-7lszflti6pcputd1mrilptht5 10.124.131.251:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.

#

2.      Create overlay network

    docker network create --driver overlay --attachable ollama_net

3.      Prepare persistent volumes

    sudo mkdir -p /srv/docker/nginx_data
    sudo chmod -R 777 /srv/docker/nginx_data

4.  Create ollama_stack.yml:
    version: "3.9"

networks:
ollama_net:
external: true

volumes:
nginx_data:
driver: local

services:

# nginx:

# image: nginx:stable

# networks:

# - ollama_net

# ports:

# - "80:80"

# - "443:443"

# environment:

# - TZ=America/Los_Angeles

# volumes:

# - nginx_data:/usr/share/nginx/html

# deploy:

# replicas: 1

# restart_policy:

# condition: on-failure

ollama:
image: harbor.mt-ss.cdcr.ca.gov/ai/ollama-with-models:amd64
networks: - ollama_net
ports: - "11434:11434"
environment: - OLLAMA_FLASH_ATTENTION=true - OLLAMA_HOST=0.0.0.0 - OLLAMA_NUM_THREADS=8 - OLLAMA_PORT=11434 - TZ=America/Los_Angeles
volumes: - /var/run/docker.sock:/var/run/docker.sock
deploy:
replicas: 1
restart_policy:
condition: on-failure

open-webui:
image: harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:main
networks: - ollama_net
ports: - "8080:8080"
environment: - CORS_ALLOW_HEADERS=Content-Type,Authorization - CORS_ALLOW_METHODS=GET,POST,PUT,DELETE,OPTIONS - CORS_ALLOW_ORIGIN=\* - ENABLE_OLLAMA_API=true - ENABLE_RAG_WEB_LOADER=false - ENABLE_RAG_WEB_SEARCH=false - ENABLE_SIGNUP_PASSWORD_CONFIRMATION=true - ENABLE_SIGNUP=true - ENV=dev - GLOBAL_LOG_LEVEL=DEBUG - OLLAMA_BASE_URL=http://ollama:11434 - RAG_EMBEDDING_ENGINE= - RAG_EMBEDDING_MODEL= - RAG_RERANKING_MODEL= - TZ=America/Los_Angeles - USE_EMBEDDING_MODEL_DOCKER= - USE_RERANKING_MODEL_DOCKER=
volumes: - /var/run/docker.sock:/var/run/docker.sock
deploy:
replicas: 1
restart_policy:
condition: on-failure

5. Create Lifecycle Bash Scripts:
   touch start_stack.sh
   cat <<EOF | tee start_stack.sh
   #!/bin/bash
   STACK_NAME=ollama
   docker stack deploy -c ollama-stack.yml --prune $STACK_NAME
   EOF

touch stop_stack.sh
cat <<EOF | tee stop_stack.sh
#!/bin/bash
STACK_NAME=ollama
docker stack rm $STACK_NAME
docker volume prune --all --force
EOF

touch restart_stack.sh
cat <<EOF | tee restart_stack.sh
#!/bin/bash
STACK_NAME=ollama
./stop_stack.sh
sleep 10
./start_stack.sh
EOF

# Make them executable:

chmod +x start_stack.sh stop_stack.sh restart_stack.sh

---

# Remove all Nodes from Swarm:

---

## From each NON-Leader VM type:

docker swarm leave --force

#

## Wait until Status is set to Down on all, but the Leader node, via "docker node ls" command.

docker node ls

# Only do the node removal if there is more than one node

docker node node1 node2 --force

#

## Finally make the Leader leave the docker swarm:

docker swarm leave --force

rm -rf ollama-stack
git clone https://github.com/CDCR-KevinBaroni/ollama-stack.git

http://10.124.131.251:8080
Admin Account
Name: Kevin Baroni
Email: kevin.baroni@cdcr.ca.gov
Password: Password1234

curl http://localhost:11434/api/tags | jq
curl http://localhost:11434/api/ps | jq
curl -X POST http://localhost:11434/api/show -d '{"name": "llama3.2"}' | jq

curl http://localhost:11434/api/generate -d '{
"model": "llama3.2",
"prompt":"Why cant humans and dogs breath under water?"
}'

Ollama Monitor
https://github.com/Xza85hrf/Ollama_monitor

10.4.130.102 (FDC01DKCPGDB01)
Username: pst_admin
Password: NNc@P2022
10.4.130.103 (FDC01TKCPGDB01)
10.4.130.101 (FDC01QKCPGDB01)
10.4.130.104 (FDC01PKCPGDB01)

REQ0250621/RITM0250663/SCTASK0244015 - SAR - MT2 - Update Subnet, add access to new PostgreSQL servers
This SAR does the following::
• Adds access to the new PostgreSQL servers for the Dev, Test, Stage & Prod clusters in the MT.

SAR Doc Link:
https://cdcr.sharepoint.com/sites/cdcr_eis_ops_is_sar/TigerTeamLib/OMS/SAR-EIS-MiddleTier-2.0%20-%20TKG-Prod.docx
Version: 52.0

REQ0251020/RITM0251062/SCTASK0244392 - SAR - DataCenter VPN - Update Subnets, Allow additional ports for Datacenter VPN connection to MT2 and Tanzu infrastructure
This SAR update: Allow additional ports for Datacenter VPN connection to MT2 and Tanzu infrastructure.

SAR Doc Link:
https://cdcr.sharepoint.com/sites/cdcr_eis_ops_is_sar/TigerTeamLib/Infra_Eng_Ops/VPN/SAR-Infra-VPN_Datacenter_FDC_Primary_Support-Prod.docx
Version: 158.0

---

# Start the Ollama listener

export OLLAMA_HOST=127.0.0.1:11500
export OLLAMA_MODELS=/testdata/ollama_stack/ollama/models
ollama serve

# Conservative

export OLLAMA_HOST=127.0.0.1:11500
export OLLAMA_MODELS=/testdata/ollama_stack/ollama/models
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_NUM_THREADS=1
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_KEEP_ALIVE=0
export OLLAMA_DEBUG=1
ollama serve

# Multithreaded fast quadrent

export OLLAMA_HOST=127.0.0.1:11500
export OLLAMA_MODELS=/testdata/ollama_stack/ollama/models
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KEEP_ALIVE=10m

# Supports standard kv cache quantization formats like f16 and

# (if built with kv cache quantization enabled) q4_0, q4_1, q5_0, q5_1, q8_0.

export OLLAMA_KV_CACHE_TYPE=q4_0
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_MAX_QUEUE=32
export OLLAMA_NUM_PARALLEL=4
export OLLAMA_NUM_THREADS=32
ollama serve
