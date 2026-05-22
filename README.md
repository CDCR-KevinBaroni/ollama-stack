# ollama-stack

1. Initialize Swarm (single node)
docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
#
$ docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
Swarm initialized: current node (rl0596bcajjqu4y9cyfi6eoqk) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token REDACTED

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
#
docker node ls
#
2. 	Create overlay network
docker network create --driver overlay --attachable ollama_net
#
# Firewall Changes - beyond those already done
sudo firewall-cmd --list-all-zones
sudo firewall-cmd --zone=public --add-port=80/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8080/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8081/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8082/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8083/tcp --permanent
sudo firewall-cmd --zone=public --add-port=8084/tcp --permanent
sudo firewall-cmd --zone=public --add-port=11434/tcp --permanent
# Reload firewalld service
sudo firewall-cmd --reload

# via curl on the Docker Registry VM:
docker login harbor.mt-ss.cdcr.ca.gov --username admin --password REDACTED

3. 	Prepare persistent volumes
sudo mkdir -p /testdata/ollama_stack/ollama/data
sudo chmod -R 777 /testdata/ollama_stack/ollama/data
#
sudo mkdir -p /testdata/ollama_stack/open-webui
sudo chmod -R 777 /testdata/ollama_stack/open-webui
#
sudo mkdir -p /testdata/ollama_stack/nginx
sudo chmod -R 777 /testdata/ollama_stack/nginx


4. Create ollama_stack.yml:
version: "3.9"

networks:
  ollama_net:
    external: true

volumes:
  nginx_data:
    driver: local

services:
#  nginx:
#    image: nginx:stable
#    networks:
#      - ollama_net
#    ports:
#      - "80:80"
#      - "443:443"
#    environment:
#      - TZ=America/Los_Angeles
#    volumes:
#      - nginx_data:/usr/share/nginx/html
#    deploy:
#      replicas: 1
#      restart_policy:
#        condition: on-failure

  ollama:
    image: harbor.mt-ss.cdcr.ca.gov/ai/ollama-with-models:amd64
    networks:
      - ollama_net
    ports:
      - "11434:11434"
    environment:
      - OLLAMA_FLASH_ATTENTION=true
      - OLLAMA_HOST=0.0.0.0 
      - OLLAMA_NUM_THREADS=8
      - OLLAMA_PORT=11434
      - TZ=America/Los_Angeles
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure

  open-webui:
    image: harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:main
    networks:
      - ollama_net
    ports:
      - "8080:8080"
    environment:
      - CORS_ALLOW_HEADERS=Content-Type,Authorization
      - CORS_ALLOW_METHODS=GET,POST,PUT,DELETE,OPTIONS
      - CORS_ALLOW_ORIGIN=*
      - ENABLE_OLLAMA_API=true
      - ENABLE_RAG_WEB_LOADER=false
      - ENABLE_RAG_WEB_SEARCH=false
      - ENABLE_SIGNUP_PASSWORD_CONFIRMATION=true
      - ENABLE_SIGNUP=true
      - ENV=dev
      - GLOBAL_LOG_LEVEL=DEBUG
      - OLLAMA_BASE_URL=http://ollama:11434
      - RAG_EMBEDDING_ENGINE=
      - RAG_EMBEDDING_MODEL=
      - RAG_RERANKING_MODEL=
      - TZ=America/Los_Angeles
      - USE_EMBEDDING_MODEL_DOCKER=
      - USE_RERANKING_MODEL_DOCKER=
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
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

------------------------------
# Remove all Nodes from Swarm:
------------------------------
## From each NON-Leader VM type:
docker swarm leave --force
#
## Wait until Status is set to Down on all, but the Leader node, via "docker node ls" command.
docker node ls
# Only do the node removal if there is more than one node
docker node rm node1 node2  --force
#
## Finally make the Leader leave the docker swarm:
docker swarm leave --force


rm -rf ollama-stack
git clone https://github.com/CDCR-KevinBaroni/ollama-stack.git



http://10.124.131.251:8080/
http://10.124.131.251:8080/docs
http://web-ui.mt-sb.cdcr.ca.gov:8080/
http://web-ui.mt-sb.cdcr.ca.gov:8080/docs
---
http://10.124.131.251/
http://web-ui.mt-sb.cdcr.ca.gov/
http://web-ui.mt-sb.cdcr.ca.gov/docs
Admin Account
Name: Kevin Baroni
Email: kevin.baroni@cdcr.ca.gov
Password: Password1234

curl http://127.0.0.1:11434/api/tags | jq
curl http://127.0.0.1:11434/api/ps | jq
curl -X POST http://127.0.0.1:11434/api/show -d '{"name": "llama3.2"}' | jq


curl http://127.0.0.1:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt":"Why cant humans and dogs breath under water?"
}'

curl http://127.0.0.1:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "hi"
}'
curl http://127.0.0.1:11434/api/generate -d '{
  "model": "llama3.2:3b",
  "prompt": "hi",
  "options": {"num_thread": 32, "num_ctx": 2048, "num_batch": 512}
}'
curl http://127.0.0.1:11434/api/generate -d '{
  "model": "qwen3.5:9b",
  "prompt": "hi"
}'
curl http://127.0.0.1:11434/api/generate -d '{
  "model": "qwen3.5:9b",
  "prompt": "hi",
  "options": {"num_thread": 32, "num_ctx": 2048, "num_batch": 512}
}'
curl http://127.0.0.1:11434/api/generate -d '{
  "model": "deepseek-r1:8b",
  "prompt": "hi",
  "options": {"num_thread": 32, "num_ctx": 2048, "num_batch": 512}
}'


ollama run qwen3.5:9b "Hi"
ollama run llama3.2:3b "Why cant humans and dogs breath under water?"

------------------------------
Ollama Monitor
https://github.com/Xza85hrf/Ollama_monitor

Swarmpit Monitor
http://10.124.131.251:8081/


https://ollama.com/
------------------------------
https://github.com/CDCR-KevinBaroni/ollama_stack


# OLLAMA
docker pull ghcr.io/open-webui/open-webui:main
docker tag  ghcr.io/open-webui/open-webui:main  harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:main
docker push harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:main
#
docker pull mkildare15/ollama-with-models:1.2
docker tag  mkildare15/ollama-with-models:1.2  harbor.mt-ss.cdcr.ca.gov/ai/ollama-with-models:1.2
docker push harbor.mt-ss.cdcr.ca.gov/ai/ollama-with-models:1.2


#
ctxd
kubectl delete -f open-webui-deployment.yaml --grace-period=0 --force
kubectl delete -f ollama-deployment.yaml --grace-period=0 --force
#
ctxd
kubectl apply -f open-webui-deployment.yaml
kubectl apply -f ollama-deployment.yaml

http://web-ui.mt-sb.cdcr.ca.gov/
http://web-ui.mt-sb.cdcr.ca.gov/docs




curl -fsSL https://ollama.com/install.sh | sh


docker pull ghcr.io/open-webui/open-webui:latest
docker tag  ghcr.io/open-webui/open-webui  harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:latest
docker tag  ghcr.io/open-webui/open-webui  harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:0.9.5
docker push harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:latest
docker push harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:0.9.5


docker pull ollama/ollama:latest
docker tag  ollama/ollama  harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:latest
docker tag  ollama/ollama  harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:24.04
docker tag  ollama/ollama  harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:amd64
docker push harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:latest
docker push harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:24.04
docker push harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:amd64

      # Persist Ollama state
      - /testdata/ollama_stack/ollama/state_data:/root/.ollama
      # Map host model directory
      - /testdata/ollama_stack/ollama/models:/root/.ollama/models


HTTP_PROXY=http://agency-proxy.lb.cdcr.ca.gov:8080/
http_proxy=http://agency-proxy.lb.cdcr.ca.gov:8080/
HTTPS_PROXY=http://agency-proxy.lb.cdcr.ca.gov:8080/
https_proxy=http://agency-proxy.lb.cdcr.ca.gov:8080/
no_proxy=10.124.131.251,10.124.130.121,cdcr.ca.gov,*.cdcr.ca.gov,localhost,127.0.0.0/24,10.0.0.0/8,153.48.0.0/16,172.0.0.0/8,192.168.0.0/16 ::1
NO_PROXY=10.124.131.251,10.124.130.121,cdcr.ca.gov,*.cdcr.ca.gov,localhost,127.0.0.0/24,10.0.0.0/8,153.48.0.0/16,172.0.0.0/8,192.168.0.0/16 ::1

docker run -it --rm \
--env OLLAMA_DEBUG=0 \
--env OLLAMA_FLASH_ATTENTION="true" \
--env OLLAMA_HOST="0.0.0.0 " \
--env OLLAMA_KEEP_ALIVE=10m \
--env OLLAMA_KV_CACHE_TYPE="q4_0" \
--env OLLAMA_MAX_LOADED_MODELS=4 \
--env OLLAMA_NUM_PARALLEL=4 \
--env OLLAMA_NUM_THREADS=30 \
--env OLLAMA_PORT=11434 \
--env TZ="America/Los_Angeles" \
--name ollama-test \
--entrypoint ["/bin/bash", "-c"] \
harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:amd64  "/bin/ollama serve"
dcr ollama-test

cdcr:cdcr-ubuntu-dev-vm-2 ~/temp
$ curl -fsSL https://ollama.com/install.sh | sh
>>> Installing ollama to /usr/local
[sudo] password for cdcr: 
>>> Downloading ollama-linux-amd64.tar.zst
######################################################################## 100.0%
>>> Creating ollama user...
>>> Adding ollama user to render group...
>>> Adding ollama user to video group...
>>> Adding current user to ollama group...
>>> Creating ollama systemd service...
>>> Enabling and starting ollama service...
Created symlink /etc/systemd/system/default.target.wants/ollama.service → /etc/systemd/system/ollama.service.
>>> The Ollama API is now available at 127.0.0.1:11434.
>>> Install complete. Run "ollama" from the command line.
WARNING: No NVIDIA/AMD GPU detected. Ollama will run in CPU-only mode.

cdcr:cdcr-ubuntu-dev-vm-2 ~/temp
$ ollama

  To use   kimi-k2.6:cloud, please sign in.                                                                                                                                                                                                 
                                                                                                                                                                                                                                            
  Navigate to:                                                                                                                                                                                                                              
    https://ollama.com/connect?name=cdcr-ubuntu-dev-vm-2&key=c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUIyV0NrVXd0TGlXZnF5Q1FjTWl2MklNWDVxQ2V5TmN0N1F0RFFxTVhVQXo                                                                    
                                                                                                                                                                                                                                            
  ⠹ Waiting for sign in to complete...
---
Your new public key is: 

ssh-ed25519 REDACTED

Error: listen tcp 127.0.0.1:11434: bind: address already in use
---
Environment Variables for Ollama
https://gist.github.com/kwame-mintah/7ffd62d13f7e82318dd62d097a1f3608


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

---
sudo systemctl stop ollama
#
sudo vi /etc/systemd/system/ollama.service
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11435"
Environment="OLLAMA_MODELS=/home/cdcr/ollama_models"
#
sudo systemctl daemon-reload
sudo systemctl start ollama
sudo systemctl status ollama
#
sudo systemctl daemon-reload
sudo systemctl restart ollama
sudo systemctl status ollama
---
Your new public key is: 

ssh-ed25519 REDACTED

Error: listen tcp 127.0.0.1:11434: bind: address already in use




ollama pull llama3.2:3b
ollama pull qwen3.5:9b
ollama pull mistral:7b
ollama pull deepseek-r1:8b
ollama pull llama3.1:8b
ollama pull codellama:7b
---
ollama pull gemma4:e4b

# Create a compressed archive file
folderName=ollama_models
sudo tar --create --recursion --gzip --verbose --file=${folderName}.gz.tar ${folderName}
# View what's in the tar file
folderName=ollama_models
tar -tf ${folderName}.gz.tar
# Extract/Decompress a compressed archive
cd /testdata/ollama/.ollama/
folderName=ollama_models
sudo tar --extract --gunzip --verbose --file=${folderName}.gz.tar


# Endpoints Blocked
https://registry.ollama.ai/v2/library/llama3.2/manifests/3b
https://ollama.com/api/experimental/model-recommendations
https://ollama.com/api/tags?ts=1778722790

