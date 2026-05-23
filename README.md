# ollama-stack

1. Initialize Swarm (single node)

```
   docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')

#
$ docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
Swarm initialized: current node (rl0596bcajjqu4y9cyfi6eoqk) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-4v8y96x2tqnr9yqafwblb920nk3voc484qybhv27fmu1gongux-0q10wz1ugoxwbagau7p7xpot9 192.168.88.104:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.

#
docker node ls

#
```

2.          Create overlay network

```
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
```

3.          Prepare persistent volumes

```
sudo mkdir -p /var/ollama_stack/ollama/data
sudo chmod -R 777 /var/ollama_stack/ollama/data
sudo mkdir -p /var/ollama_stack/ollama/models
sudo chmod -R 777 /var/ollama_stack/ollama/models
#
sudo mkdir -p /var/ollama_stack/open-webui
sudo chmod -R 777 /var/ollama_stack/open-webui
#
sudo mkdir -p /var/ollama_stack/nginx
sudo chmod -R 777 /var/ollama_stack/nginx
```

4. Create ollama_stack.yml:

```
version: "3.9"

networks:
  ollama_net:
    external: true

services:
  # nginx:
  #   image: nginx:stable
  #   networks:
  #     - ollama_net
  #   ports:
  #     - "80:80"
  #     - "443:443"
  #     - "8080:8080"
  #   environment:
  #     - TZ=America/Los_Angeles
  #   volumes:
  #     # Nginx config
  #     - /home/midtier/ollama-stack/nginx.conf:/opt/bitnami/nginx/conf/nginx.conf
  #     # Nginx html files
  #     - /var/ollama_stack/nginx:/usr/share/nginx/html
  #   deploy:
  #     replicas: 1
  #     restart_policy:
  #       condition: on-failure

  ollama:
    image: ollama/ollama:latest
    networks:
      - ollama_net
    ports:
      - "11434:11434"
    # OLLAMA_KV_CACHE_TYPE values q4_0, q4_1, q5_0, q5_1, q8_0, f16
    environment:
      - OLLAMA_DEBUG=0
      - OLLAMA_FLASH_ATTENTION=true
      - OLLAMA_HOST=0.0.0.0
      - OLLAMA_KEEP_ALIVE=10m
      - OLLAMA_KV_CACHE_TYPE=f16
      - OLLAMA_MAX_LOADED_MODELS=4
      - OLLAMA_NUM_PARALLEL=4
      - OLLAMA_NUM_THREADS=32
      - OLLAMA_ORIGINS="*"
      - OLLAMA_PORT=11434
      - TZ=America/Los_Angeles
    # This preloads multiple models sets the default model in the first "ollama run" statement
    entrypoint: ["/bin/bash", "-c"]
    command:
      [
        "/bin/ollama serve & \
         sleep 5 && \
         /bin/ollama pull llama3.2:3b && \
         /bin/ollama pull codellama:7b && \
         /bin/ollama pull mistral:7b && \
         /bin/ollama pull deepseek-r1:8b && \
         /bin/ollama pull llama3.1:8b && \
         /bin/ollama pull qwen3.5:9b && \
         /bin/ollama run llama3.2:3b --keepalive 1440m >/dev/null 2>&1 & \
         /bin/ollama run codellama:7b --keepalive 1440m >/dev/null 2>&1 & \
         /bin/ollama run mistral:7b --keepalive 1440m >/dev/null 2>&1 & \
         /bin/ollama run deepseek-r1:8b --keepalive 1440m >/dev/null 2>&1 & \
         /bin/ollama run llama3.1:8b --keepalive 1440m >/dev/null 2>&1 & \
         /bin/ollama run qwen3.5:9b --keepalive 1440m >/dev/null 2>&1 & \
         wait"
      ]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      # Persist Ollama state
      - /var/ollama_stack/ollama/data:/root/.ollama
      # Persistent models
      - /var/ollama_stack/ollama/models:/root/.ollama/models
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: "8.0"
          memory: 32G
        reservations:
          cpus: "4.0"
          memory: 16G

  open-webui:
    image: ghcr.io/open-webui/open-webui:main
    networks:
      - ollama_net
    ports:
      - "80:8080"
      - "8080:8080"
    environment:
      - CORS_ALLOW_HEADERS=Content-Type,Authorization
      - CORS_ALLOW_METHODS=GET,POST,PUT,DELETE,OPTIONS
      - CORS_ALLOW_ORIGIN=*
      - DEFAULT_MODEL=llama3.2:3b
      - ENABLE_OLLAMA_API=true
      - ENABLE_RAG_WEB_LOADER=false
      - ENABLE_RAG_WEB_SEARCH=false
      - ENABLE_SIGNUP_PASSWORD_CONFIRMATION=true
      - ENABLE_SIGNUP=true
      - ENV=dev
      - GLOBAL_LOG_LEVEL=INFO
      - OLLAMA_BASE_URL=http://ollama:11434
      - RAG_EMBEDDING_ENGINE=
      - RAG_EMBEDDING_MODEL=
      - RAG_RERANKING_MODEL=
      - TZ=America/Los_Angeles
      - USE_EMBEDDING_MODEL_DOCKER=
      - USE_RERANKING_MODEL_DOCKER=
      - WEBUI_NAME=CDCR
      # Performance tuning settings
      - ENABLE_BASE_MODELS_CACHE=true
      - MODELS_CACHE_TTL=300
      - THREAD_POOL_SIZE=42
      - WEBUI_CONCURRENCY="32"
      - WEBUI_MAX_REQUESTS="2048"
      - WEBUI_TIMEOUT="120"
      - WEBUI_WORKERS="4"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/ollama_stack/open-webui:/app/backend/data
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
      resources:
        limits:
          cpus: "8.0"
          memory: 8G
        reservations:
          cpus: "2.0"
          memory: 4G
```

5. Create Lifecycle Bash Scripts:

```
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

#
# Make them executable:
chmod +x start_stack.sh stop_stack.sh restart_stack.sh
---
# Remove all Nodes from Swarm:
## From each NON-Leader VM type:
docker swarm leave --force

#
## Wait until Status is set to Down on all, but the Leader node, via "docker node ls" command.
docker node ls

# Only do the node removal if there is more than one node
docker node rm node1 node2 --force

#
## Finally make the Leader leave the docker swarm:

docker swarm leave --force

rm -rf ollama-stack
git clone https://github.com/CDCR-KevinBaroni/ollama-stack.git

```

http://127.0.0.1:8080/

http://127.0.0.1:8080/docs

http://web-ui.mt-sb.cdcr.ca.gov:8080/

http://web-ui.mt-sb.cdcr.ca.gov:8080/docs

---

http://127.0.0.1/

http://web-ui.mt-sb.cdcr.ca.gov/

http://web-ui.mt-sb.cdcr.ca.gov/docs

```
Admin Account
Name: Kevin Baroni
Email: kevin.a.baroni@gmail.com
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
```

---

Ollama Monitor
https://github.com/Xza85hrf/Ollama_monitor

Swarmpit Monitor
http://127.0.0.1:8081/

## https://ollama.com/

https://github.com/CDCR-KevinBaroni/ollama_stack

# OLLAMA

```

docker pull ghcr.io/open-webui/open-webui:main
docker tag ghcr.io/open-webui/open-webui:main harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:main
docker push harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:main
#
docker pull mkildare15/ollama-with-models:1.2
docker tag mkildare15/ollama-with-models:1.2 harbor.mt-ss.cdcr.ca.gov/ai/ollama-with-models:1.2
docker push harbor.mt-ss.cdcr.ca.gov/ai/ollama-with-models:1.2
#
ctxd
kubectl delete -f open-webui-deployment.yaml --grace-period=0 --force
kubectl delete -f ollama-deployment.yaml --grace-period=0 --force
#
ctxd
kubectl apply -f open-webui-deployment.yaml
kubectl apply -f ollama-deployment.yaml
```

http://web-ui.mt-sb.cdcr.ca.gov/
http://web-ui.mt-sb.cdcr.ca.gov/docs

```
curl -fsSL https://ollama.com/install.sh | sh

docker pull ghcr.io/open-webui/open-webui:latest
docker tag ghcr.io/open-webui/open-webui harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:latest
docker tag ghcr.io/open-webui/open-webui harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:0.9.5
docker push harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:latest
docker push harbor.mt-ss.cdcr.ca.gov/ai/open-webui/open-webui:0.9.5

docker pull ollama/ollama:latest
docker tag ollama/ollama harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:latest
docker tag ollama/ollama harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:24.04
docker tag ollama/ollama harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:amd64
docker push harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:latest
docker push harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:24.04
docker push harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:amd64

      # Persist Ollama state
      - /var/ollama_stack/ollama/state_data:/root/.ollama
      # Map host model directory
      - /var/ollama_stack/ollama/models:/root/.ollama/models

HTTP*PROXY=http://agency-proxy.lb.cdcr.ca.gov:8080/
http_proxy=http://agency-proxy.lb.cdcr.ca.gov:8080/
HTTPS_PROXY=http://agency-proxy.lb.cdcr.ca.gov:8080/
https_proxy=http://agency-proxy.lb.cdcr.ca.gov:8080/
no_proxy=127.0.0.1,10.124.130.121,cdcr.ca.gov,*.cdcr.ca.gov,localhost,127.0.0.0/24,10.0.0.0/8,153.48.0.0/16,172.0.0.0/8,192.168.0.0/16 ::1
NO*PROXY=127.0.0.1,10.124.130.121,cdcr.ca.gov,*.cdcr.ca.gov,localhost,127.0.0.0/24,10.0.0.0/8,153.48.0.0/16,172.0.0.0/8,192.168.0.0/16 ::1

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
harbor.mt-ss.cdcr.ca.gov/ai/ollama-no-models/ollama:amd64 "/bin/ollama serve"
dcr ollama-test

cdcr:cdcr-ubuntu-dev-vm-2 ~/temp
$ curl -fsSL https://ollama.com/install.sh | sh

> > > Installing ollama to /usr/local
> > > [sudo] password for cdcr:
> > > Downloading ollama-linux-amd64.tar.zst
> > > ######################################################################## 100.0%
> > > Creating ollama user...
> > > Adding ollama user to render group...
> > > Adding ollama user to video group...
> > > Adding current user to ollama group...
> > > Creating ollama systemd service...
> > > Enabling and starting ollama service...
> > > Created symlink /etc/systemd/system/default.target.wants/ollama.service → /etc/systemd/system/ollama.service.
> > > The Ollama API is now available at 127.0.0.1:11434.
> > > Install complete. Run "ollama" from the command line.
> > > WARNING: No NVIDIA/AMD GPU detected. Ollama will run in CPU-only mode.

cdcr:cdcr-ubuntu-dev-vm-2 ~/temp
$ ollama

To use kimi-k2.6:cloud, please sign in.

Navigate to:
 https://ollama.com/connect?name=cdcr-ubuntu-dev-vm-2&key=c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUIyV0NrVXd0TGlXZnF5Q1FjTWl2MklNWDVxQ2V5TmN0N1F0RFFxTVhVQXo

## ⠹ Waiting for sign in to complete...

Your new public key is:

ssh-ed25519 REDACTED

## Error: listen tcp 127.0.0.1:11434: bind: address already in use


Environment Variables for Ollama
https://gist.github.com/kwame-mintah/7ffd62d13f7e82318dd62d097a1f3608

# Start the Ollama listener
export OLLAMA_HOST=127.0.0.1:11434
export OLLAMA_MODELS=/var/ollama_stack/ollama/models
ollama serve

# Conservative
export OLLAMA_HOST=127.0.0.1:11500
export OLLAMA_MODELS=/var/ollama_stack/ollama/models
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_NUM_THREADS=1
export OLLAMA_MAX_LOADED_MODELS=1
export OLLAMA_KEEP_ALIVE=0
export OLLAMA_DEBUG=1
ollama serve

# Multithreaded fast quadrent
export OLLAMA_HOST=127.0.0.1:11500
export OLLAMA_MODELS=/var/ollama_stack/ollama/models
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
cat /etc/systemd/system/ollama.service
sudo vi /etc/systemd/system/ollama.service
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_MODELS=/var/ollama_stack/ollama/models"
#
sudo systemctl daemon-reload
sudo systemctl start ollama
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
cd /var/ollama/.ollama/
folderName=ollama_models
sudo tar --extract --gunzip --verbose --file=${folderName}.gz.tar
```

# Endpoints Blocked

https://registry.ollama.ai/v2/library/llama3.2/manifests/3b

https://ollama.com/api/experimental/model-recommendations

https://ollama.com/api/tags?ts=1778722790
