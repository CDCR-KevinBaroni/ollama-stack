# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Infrastructure for the **ollama_stack** — Ollama + Open WebUI running on a single Windows 11 laptop (KABC-DEV-MINI, i7-1360P, 64 GB RAM, CPU-only) inside WSL2. No application source code; just deployment configs, lifecycle scripts, and operational docs.

Two deployment paths coexist in this repo, in two folders:

- **[systemd/](systemd/) — primary, currently running.** Native Ollama (via the official installer) + Open WebUI from a Python venv. Faster than the Docker path on this hardware and avoids the WSL2 9P filesystem penalty for model mmap.
- **[docker-swarm/](docker-swarm/) — fallback, not running.** Original Docker Swarm stack. Preserved as a rollback path and parity reference. Source data at `/mnt/d/ollama_stack/` is intact.

Migration from the Docker stack to systemd happened on 2026-05-27. See [systemd/MIGRATION.md](systemd/MIGRATION.md) for the cutover record and [systemd/README.md](systemd/README.md) for current ops.

## Quick orientation

Working directory locations to understand:

| Path | What's there |
|---|---|
| `/etc/systemd/system/ollama.service.d/override.conf` | Tuning overlay over the upstream `ollama.service`. Source of truth in repo: [systemd/ollama.service.d-override.conf](systemd/ollama.service.d-override.conf). |
| `/etc/systemd/system/open-webui.service`, `/etc/systemd/system/ollama-warmup.service` | Installed by `systemd/install.sh`. Source files in [systemd/](systemd/). |
| `/etc/default/open-webui` | `EnvironmentFile=` for open-webui.service — holds the Tavily key. 0640 root:open-webui. Not in repo. Template in [systemd/open-webui.env.example](systemd/open-webui.env.example). |
| `/opt/open-webui/venv` | Python 3.11 venv from deadsnakes PPA. CPU-only torch (`+cpu` build) to avoid 5 GB of unused CUDA libs. |
| `/var/lib/ollama/models` | 27 GB of model blobs (codellama, deepseek-r1, gemma3, llama3.1, llama3.2, mistral, nomic-embed-text, qwen3.5), on WSL2-native ext4. |
| `/var/lib/open-webui` | Open WebUI runtime data: `webui.db` (SQLite + WAL), `vector_db/`, `cache/`, `uploads/`. |
| `/mnt/d/ollama_stack/` | The pre-migration data. **Do not delete** until you're confident in the systemd setup — it's the rollback snapshot. |

## Common operations

```bash
# Status
sudo systemctl status ollama ollama-warmup open-webui

# Logs (follow)
sudo journalctl -u ollama -f
sudo journalctl -u open-webui -f

# API
curl -s http://127.0.0.1:11434/api/tags | jq '.models[].name'
curl -s http://127.0.0.1:11434/api/ps   | jq

# Apply changes to systemd/ config files
cd systemd && sudo ./install.sh    # idempotent; copies files to /etc/, daemon-reloads, restarts units

# Benchmark thread count after hardware/kernel change
cd systemd && sudo ./tune-threads.sh

# Rollback to Docker Swarm
cd systemd && sudo ./uninstall.sh
cd ../docker-swarm && ./start_stack.sh   # requires Swarm init + ollama_net per docker-swarm/README.md
```

## Tuning rationale (load-bearing decisions)

After extensive iteration the working web-search Q&A config lands at **~1m50s end-to-end with accurate cited answers** for current-events questions. The decisions below are non-obvious and each one was measured. The full multi-page rationale lives in [systemd/README.md § Web search tuning](systemd/README.md); the short version:

- **Default chat model is `llama3.2:3b`**, not `mistral:7b`. A head-to-head bake-off on identical snippet-injected prompts showed llama3.2:3b is **2× faster** with equal accuracy (44 tok/s prefill, 12 tok/s decode vs mistral's 23 tok/s / 8 tok/s). mistral:7b remains pulled and warm for the rare prompt where its longer-form prose helps, but is no longer the default.
- **Open WebUI fires up to 6 LLM calls per user message** (query rewrite, retrieval rewrite, title gen, tags, follow-up, main). Without `task.model.default` set, all 6 run on the chat model and serialize. Setting `task.model.default = "llama3.2:3b"` keeps each task sub-second; disabling `task.title.enable`, `task.tags.enable`, `task.follow_up.enable` eliminates ~25s of post-response work. Do NOT disable `task.query.search.enable` — Open WebUI's `chat_web_search_handler` throws HTTP 400 when it's off.
- **`OLLAMA_MAX_LOADED_MODELS=3`** so the chat model + reasoning model + task model can all be warm without eviction churn. With 2 slots and 3 distinct models in play, a task call evicts the chat model and the next user message pays a ~7s reload.
- **Open WebUI's default `function_calling=native` mode is a trap** for small CPU models. It passes a 27-tool blob (~8000 tokens) on every chat and expects the model to emit OpenAI-style tool_calls. Small models can't reliably hit the schema and Open WebUI silently fails to execute the malformed JSON. Setting `models.default_params.function_calling="default"` and `models.default_metadata.capabilities.builtin_tools=false` reverts to pre-fetch-and-inject snippets, which is what we actually want.
- **Tavily client is vendor-patched** at `/opt/open-webui/venv/lib/python3.11/site-packages/open_webui/retrieval/web/tavily.py`. Source of truth: [systemd/patches/tavily.py](systemd/patches/tavily.py). Sends `topic=news, days=3, include_answer=true` (the freshness levers; `days` is silently ignored when `topic=general`) and prepends Tavily's synthesized answer as a citable `[1]` source. Avoid `search_depth=advanced` — it returns 8× larger snippets which on CPU inference adds 1–2 minutes of prefill. Re-apply after every `pip install -U open-webui` via [systemd/patches/apply-tavily-patch.sh](systemd/patches/apply-tavily-patch.sh).
- **Thread count is auto-detected, not configured.** `OLLAMA_NUM_THREADS` is not a real Ollama env var (we wasted a tuning round on this). The daemon picks thread count from the active cpuset, so `CPUAffinity=0-7` in the override effectively caps inference at 8 threads. Per-request `options.num_thread` or Modelfile `PARAMETER num_thread N` is the only real lever.
- **`OLLAMA_KV_CACHE_TYPE=q4_0` + `OLLAMA_FLASH_ATTENTION=true`** — ~75% KV cache RAM savings vs f16, negligible quality loss. Flash attention is required for quantized KV cache.
- **`install.sh` does `systemctl restart` not `enable --now`** for ollama. `enable --now` no-ops on an already-running service, so env changes in the override drop-in would not be picked up. This was the cause of one diagnosis round.
- **CPU-only torch in the venv** — installing `torch --index-url https://download.pytorch.org/whl/cpu` BEFORE `pip install open-webui` saves ~5 GB of unused CUDA libraries. Pip resolves left-to-right.

## Editing the systemd config

The override drop-in pattern means: edit [systemd/ollama.service.d-override.conf](systemd/ollama.service.d-override.conf) in the repo, then `sudo systemd/install.sh` to apply. The script does explicit `systemctl restart ollama` (not just `enable --now`) so override changes are picked up whether or not ollama was already running.

For `open-webui.service` and `ollama-warmup.service`: same pattern (edit in repo, run `install.sh`).

For secrets (Tavily key, optional persistent signing keys): edit `/etc/default/open-webui` directly and `sudo systemctl restart open-webui`. The repo only holds the `.env.example` template.

## Repo conventions

- **Line endings: LF.** Editing through WSL works fine. Editing through the Windows UNC path (`\\wsl.localhost\...`) tends to introduce CRLF, which breaks shebangs and confuses systemd. `sed -i 's/\r$//' systemd/*.sh systemd/*.conf systemd/*.service systemd/*.example` cleans this up.
- **Execute bits don't survive Windows-side `chmod`** — set them from inside WSL: `chmod +x systemd/*.sh`.
- **The docker-swarm/ folder is frozen** — keep it as the rollback reference; don't migrate fixes there unless you intend to revive the Docker path.
- **The `qwen3.5:9b` tag is real** despite not appearing in Ollama's public catalog — it was pulled from somewhere onto this host historically and survived the model migration. Don't remove it from `ollama-warmup.service`.

## Known sharp edges

- **`systemctl enable --now ollama` does not restart an already-running ollama** — env changes from the override drop-in are missed. `install.sh` works around this by always doing an explicit `restart ollama` after `daemon-reload`. Don't replace this with `enable --now` "for idempotency"; it's a real trap.
- **First open-webui startup takes 30–60 seconds** (Python imports + DB migrations + sentence-transformer load). Don't conclude it's broken from a 3-second HTTP probe.
- **Open WebUI's signing keys are intentionally not set**, so user sessions invalidate on restart. To make them persistent, generate keys (`openssl rand -hex 32`) and add `SECRET_KEY=`, `JWT_SECRET_KEY=`, `WEB_SECRET_KEY=` to `/etc/default/open-webui`.
- **`CPUAffinity=0-7` is hardware-specific.** On a non-hybrid CPU or a different P-core layout, this is at best a no-op and at worst a pessimization. Always verify with `lscpu --extended` after hardware changes.
