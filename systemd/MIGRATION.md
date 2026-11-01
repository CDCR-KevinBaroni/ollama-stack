# MIGRATION.md — cutover from `docker-swarm/` to `systemd/`

This is the deliberate, ordered checklist for moving the running deployment from the Docker Swarm stack ([../docker-swarm/](../docker-swarm/)) to native systemd (this folder). Read it through once before starting — some steps are reversible (uninstall the units), others involve copying ~tens of GB of model files and you don't want to discover a typo halfway through.

## Pre-flight (do not skip)

1. **You have shell access as a user in the `sudo` group** on the WSL2 host.
2. **Free disk space on the WSL2 ext4 VHDX** ≥ size of `/mnt/d/ollama_stack/`. Check with `df -h /` (the WSL ext4 root). Models alone can be 20–40 GB depending on what's pulled. If you're tight, prune unused models from the Swarm side with `docker exec -it $(docker ps -qf name=ollama) ollama rm <tag>` first.
3. **Inventory what's currently pulled** so nothing's lost in translation:
   ```bash
   curl -s http://127.0.0.1:11434/api/tags | jq '.models[].name'
   ```
   Save the output. You'll compare against it after migration.
4. **Open WebUI chat history and user accounts** live in `/mnt/d/ollama_stack/open-webui/` — verify it's not empty and that you've identified anything you don't want to lose.
5. **Schedule a maintenance window.** The cutover involves stopping the running stack. Plan for 30–60 minutes plus model-copy time.

## Cutover

### Step 1 — One-time prerequisites

If you haven't already, complete the three prerequisites in [README.md](README.md): install Ollama via its official installer, install Open WebUI into `/opt/open-webui/venv`, and confirm `lscpu --extended` shows P-cores as logical CPUs 0–7.

> **Heads-up:** the official Ollama installer starts `ollama.service` listening on `127.0.0.1:11434` by default. The Swarm-side Ollama container is also using `:11434`. Either install Ollama first (it will fail to bind, which is fine — Step 2 frees the port) or do Step 2 before Step 1. Either order works; just don't try to run both at once.

### Step 2 — Stop the Swarm stack

```bash
cd ../docker-swarm
./stop_stack.sh
docker service ls          # should be empty
```

Optional (only if Swarm isn't used for anything else):

```bash
docker swarm leave --force
```

The Compose file, lifecycle scripts, and bind-mounted data on `/mnt/d/` are all preserved — the stack can be brought back up at any point with `./start_stack.sh`.

### Step 3 — Migrate model files to ext4

`OLLAMA_MODELS` is set to `/var/lib/ollama/models` in the override. Copy preserving the Ollama on-disk layout (blobs/, manifests/):

```bash
sudo rsync -aP --info=progress2 \
    /mnt/d/ollama_stack/ollama/models/ \
    /var/lib/ollama/models/
sudo chown -R ollama:ollama /var/lib/ollama
```

`rsync -a` preserves perms/symlinks/timestamps. `-P` shows progress. `chown` ensures the `ollama` system user (created by the upstream installer in Step 1) owns its data dir.

**Sanity check:**

```bash
sudo -u ollama ls /var/lib/ollama/models/manifests/registry.ollama.ai/library/
```

You should see a directory per pulled model (`llama3.2`, `deepseek-r1`, etc).

### Step 4 — Migrate Open WebUI data

```bash
sudo rsync -aP --info=progress2 \
    /mnt/d/ollama_stack/open-webui/ \
    /var/lib/open-webui/
sudo chown -R open-webui:open-webui /var/lib/open-webui
```

This carries user accounts, chat history, settings, and SQLite databases across.

### Step 5 — Install the systemd units

```bash
cd ../systemd
sudo ./install.sh
```

The script prints `systemctl status` for all three units at the end. Expect:

- `ollama.service` → `active (running)`
- `ollama-warmup.service` → `active (exited)` after the warmup completes (~30–60s for two models)
- `open-webui.service` → `active (running)`

If `open-webui.service` is failing, it's almost always one of: venv not installed at `/opt/open-webui/venv`, `open-webui` user lacks ownership of `/var/lib/open-webui`, or port 8080 is bound by something else. `journalctl -u open-webui -n 50` will tell you which.

### Step 6 — Configure secrets and restart

```bash
sudo $EDITOR /etc/default/open-webui   # set TAVILY_API_KEY at minimum
sudo systemctl restart open-webui
```

### Step 7 — Smoke test

```bash
# 1. Ollama is up and sees all migrated models
curl -s http://127.0.0.1:11434/api/tags | jq '.models[].name'
# Compare against the inventory from pre-flight step 3 -- should match.

# 2. Two warm models are loaded
curl -s http://127.0.0.1:11434/api/ps | jq

# 3. A real generation works
curl -s http://127.0.0.1:11434/api/generate \
    -d '{"model":"llama3.2:3b","prompt":"reply with the single word ok","stream":false}' \
    | jq -r .response

# 4. Open WebUI loads in the browser
xdg-open http://127.0.0.1:8080

# 5. Log in with your existing account -- chat history should be intact.
```

### Step 8 — Benchmark vs the old setup

Run the perf-validation commands from [../docker-swarm/CLAUDE.md](../CLAUDE.md) (or the perf plan) and compare:

```bash
time curl -s http://127.0.0.1:11434/api/generate \
    -d '{"model":"llama3.2:3b","prompt":"explain mmap in 3 sentences","stream":false}' \
    | jq .eval_duration
```

Expect single-request `eval_duration` to drop noticeably vs the Swarm baseline. If it doesn't, run [tune-threads.sh](tune-threads.sh) to find a better `OLLAMA_NUM_THREADS` value for this exact host.

## Rollback

If the native deployment misbehaves:

```bash
cd ../systemd && sudo ./uninstall.sh
cd ../docker-swarm && ./start_stack.sh
```

The Swarm stack will come back up reading the original `/mnt/d/ollama_stack/` data — it was never touched (only copied from). The rsync did not delete the source. `uninstall.sh` leaves `/var/lib/ollama` and `/var/lib/open-webui` intact in case you want to retry.

## After a successful cutover

These are cleanup tasks, **not** part of the cutover itself. Defer until you're confident the new setup is stable (a week or two of normal use is reasonable).

- Decide whether to delete `/mnt/d/ollama_stack/` to free the Windows D: drive. Until you do, you have a complete rollback snapshot.
- Update the root `CLAUDE.md` to point at this folder as the primary deployment and `docker-swarm/` as the fallback.
- Add `ollama.service.d-override.conf` to your dotfiles/backup workflow if you have one — the override is on `/etc/`, not in this repo, after install.

## What can go wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| `install.sh` says "ollama not installed" | Step 1 not done | Run `curl -fsSL https://ollama.com/install.sh \| sh` |
| `install.sh` warns about open-webui not found | Venv not at `/opt/open-webui/venv` | Follow Step 1, second prerequisite |
| `ollama-warmup` exits with error in journalctl | Model tag in unit file doesn't exist on this host | Edit `ollama-warmup.service`, remove the missing model's `ExecStart=` line, `systemctl daemon-reload`, `systemctl restart ollama-warmup` |
| First-token latency feels slower than Swarm | `CPUAffinity=0-7` doesn't match this host's P-core numbering | `lscpu --extended`, edit `CPUAffinity=` in `/etc/systemd/system/ollama.service.d/override.conf`, `systemctl daemon-reload && systemctl restart ollama` |
| Open WebUI shows no chat history | Step 4 didn't run, or ran as wrong user | Re-run Step 4 with correct chown |
| Both Ollama instances try to bind :11434 | Step 1 ran before Step 2 and Swarm is still up | Run Step 2; then `systemctl restart ollama` |
