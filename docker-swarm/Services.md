# AI Prompt: In ubuntu, can "open web ui" and  "ollama" be run together as ubuntu services (not docker services) and if so, how?

#### Ollama makes this incredibly easy. Its native Linux installer automatically generates a system user and a systemd config block for you.

## Part 1: Setting up the Ollama Service

1. **Run the installer:**
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ```
2. **Verify it's running as a service:**
   ```bash
   sudo systemctl status ollama
   (It will automatically listen locally at [http://127.0.0.1:11434](http://127.0.0.1:11434)).
   ```

## Part 2: Installing Open WebUI via Python
Ubuntu 22.04 and 24.04 mandate the use of Python virtual environments (venv) to prevent external pip packages from breaking system tools.

1. **Install Python dependencies:**
   ```bash
   sudo apt update
   sudo apt install python3-pip python3-venv -y
   ```
   
2. **Create an isolated directory and environment:**
   We will build this in your user directory. Run these commands step-by-step:

   ```bash
   mkdir ~/open-webui-service
   cd ~/open-webui-service
   python3 -m venv venv
   ```

3. **Install Open WebUI inside the environment:**
   ```bash
   ./venv/bin/pip install open-webui
   ```

4. **Locate your executable path:**
   Run `pwd` to see your current directory path. Your direct path to launch Open WebUI will be:

   `/home/YOUR_USERNAME/open-webui-service/venv/bin/open-webui`

---

## Part 3: Creating the Open WebUI Ubuntu Service

Now, let's build the second service file to manage the Python process.

1. **Open a new systemd unit file for Open WebUI:**

    Create the configuration template inside the system services repository:
    ```bash
    sudo nano /etc/systemd/system/open-webui.service
    ```
    
```properties
[Service]
Type=simple
User=YOUR_USERNAME
WorkingDirectory=/home/YOUR_USERNAME/open-webui-service
Environment="PATH=/home/YOUR_USERNAME/open-webui-service/venv/bin"
Environment="DATA_DIR=/home/YOUR_USERNAME/open-webui-service/data"
Environment="OLLAMA_BASE_URL=http://127.0.0.1:11434"
ExecStart=/home/YOUR_USERNAME/open-webui-service/venv/bin/open-webui serve
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```
*(Press `Ctrl + O`, `Enter` to save, and `Ctrl + X` to exit).*

### Register/Reload the service

#### Tell Ubuntu to reload systemd and start the engine, process the new configuration, turn on the application service, and pin it to activate every time your computer boots up:

    ```bash
    sudo systemctl daemon-reload
    sudo systemctl start open-webui
    sudo systemctl enable open-webui
    ```
    
## Part 4: Pull a Model and Log In
1. **Tell your native Ollama service to pull a model to chat with:**
   ```bash
   ollama pull llama3.1
   ```

2. **Open up your web browser and navigate to the native port:**
   ```text
   http://localhost:8080
   ```
   
Your web dashboard will now read your local native database directory (~/open-webui-service/data), automatically sync with your background Ollama service, and run indefinitely completely independent of Docker.


------------------------------------------------------------------------------


Managing Your Services
You can now query, stop, or view live output strings across your native backend ecosystem using these standard service flags:

```bash

# Ollama Core	
sudo journalctl -u ollama -f
sudo systemctl restart ollama
sudo systemctl status ollama

# Open WebUI Portal	
sudo journalctl -u open-webui -f	
sudo systemctl restart open-webui
sudo systemctl status open-webui

# Restart entire AI stack
echo "."
echo "Restarting entire AI stack..."
sudo systemctl daemon-reload
sudo systemctl restart ollama
sudo systemctl restart open-webui
# Status check
echo "."
echo "Wait a few seconds..."
sleep 4s
sudo systemctl status ollama
sudo systemctl status open-webui

# Load Ollama models pinned in memory
/bin/ollama run llama3.2:3b --keepalive 1440m >/dev/null 2>&1 & \
/bin/ollama run deepseek-r1:8b --keepalive 1440m >/dev/null 2>&1 & \
/bin/ollama run qwen3.5:9b --keepalive 1440m >/dev/null 2>&1 & \
wait

```

------------------------------------------------------------------------------

```bash
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
```

Your new public key is:

ssh-ed25519 REDACTED

Error: listen tcp 127.0.0.1:11434: bind: address already in use

---

```bash
#
sudo systemctl stop ollama
cat /etc/systemd/system/ollama.service
sudo vi /etc/systemd/system/ollama.service
```
```properties
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_MODELS=/mnt/d/ollama_stack/ollama/models"
#
sudo systemctl daemon-reload
sudo systemctl start ollama
sudo systemctl status ollama
```

---

Your new public key is:

ssh-ed25519 REDACTED

Error: listen tcp 127.0.0.1:11434: bind: address already in use


