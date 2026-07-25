# systemd/ — native deployment of the ollama_stack

This folder is the **recommended** way to run the ollama_stack on the KABC-DEV-MINI host: Ollama and Open WebUI as native systemd services, no Docker. The parallel [docker-swarm/](../docker-swarm/) folder remains as a fallback / parity reference.

## Why native instead of Docker

Three concrete wins on this hardware (i7-1360P, 64 GB, CPU-only, WSL2):

1. **P-core pinning.** The 1360P has 4 P-cores + 8 E-cores. `OLLAMA_NUM_THREADS=16` (the old value) spreads inference threads across both core types, and the slow E-core threads stall the fast P-core threads at every llama.cpp sync barrier. `CPUAffinity=0-7` in [ollama.service.d-override.conf](ollama.service.d-override.conf) pins all inference work to the P-cores. Doing this through Docker Swarm is fiddly; systemd makes it one line.
2. **Models off `/mnt/d/`.** The Swarm setup bind-mounts models from the Windows D: drive into WSL2 via 9P. mmap-ing model weights through 9P is several × slower than WSL2's native ext4. This folder puts models at `/var/lib/ollama/models` (ext4).
3. **No orchestration tax.** Swarm overlay networking + service-discovery DNS + container runtime overhead all buy nothing on a single node.

## One-time prerequisites

These are NOT done by [install.sh](install.sh) — they only need to happen once per host.

### 1. Install Ollama (creates the base systemd unit)

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

This creates `/etc/systemd/system/ollama.service`, the `ollama` system user, and enables/starts the service with default settings. Our [ollama.service.d-override.conf](ollama.service.d-override.conf) layers on top without modifying the upstream unit, so future Ollama upgrades won't clobber our tuning.

### 2. Install Open WebUI in a venv at `/opt/open-webui/venv`

**Python version requirement: 3.11 or 3.12.** Open WebUI pins `Requires-Python >=3.11,<3.13`. The default `python3` on this host (Ubuntu 22.04, ships 3.10) does NOT satisfy this and `pip install open-webui` will fail with "Could not find a version that satisfies the requirement". Confirm with `python3 --version` before continuing.

On Ubuntu 22.04 install Python 3.11 from the deadsnakes PPA:

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.11 python3.11-venv python3.11-dev
```

On Ubuntu 24.04, `python3.12` is already in the default apt repos:

```bash
sudo apt install -y python3.12 python3.12-venv python3.12-dev
```

Then create the venv with the 3.11/3.12 interpreter (NOT the system `python3`):

```bash
sudo useradd --system --home-dir /var/lib/open-webui --shell /usr/sbin/nologin open-webui
sudo install -d -o open-webui -g open-webui /opt/open-webui /var/lib/open-webui
sudo -u open-webui python3.11 -m venv /opt/open-webui/venv     # use python3.12 on 24.04
sudo -u open-webui /opt/open-webui/venv/bin/pip install --upgrade pip
```

**Important: install CPU-only torch BEFORE open-webui.** The default torch wheel bundles ~5 GB of CUDA libraries that are dead weight on this CPU-only host. Pip resolves left-to-right, so installing the CPU build first satisfies open-webui's torch dependency without pulling the CUDA wheel:

```bash
sudo -u open-webui /opt/open-webui/venv/bin/pip install \
    torch --index-url https://download.pytorch.org/whl/cpu
sudo -u open-webui /opt/open-webui/venv/bin/pip install open-webui
```

This brings the venv from ~7 GB down to ~2 GB. If you already installed open-webui without this step, blow away the venv and start over (see below) — pip will not retroactively swap torch builds.

If you already ran the wrong-Python version and have a broken venv, blow it away first:

```bash
sudo rm -rf /opt/open-webui/venv
```

`install.sh` checks for `/opt/open-webui/venv/bin/open-webui` and warns if it's missing — it will not create the venv for you.

### 3. Verify P-core CPU numbering on this host

`CPUAffinity=0-7` in the override assumes Linux numbers the 1360P's four P-cores (with HT siblings) as logical CPUs 0–7. Confirm before installing:

```bash
lscpu --extended | head -20
```

Look for the column labeled `MAXMHZ` — P-cores show ~5000 MHz, E-cores ~3700 MHz. If P-cores aren't 0–7, edit `CPUAffinity=` in [ollama.service.d-override.conf](ollama.service.d-override.conf) before running `install.sh`.

## Install

From this folder, as root:

```bash
sudo ./install.sh
```

Then fill in `/etc/default/open-webui` (Tavily API key, optional persistent signing keys) and restart:

```bash
sudo $EDITOR /etc/default/open-webui
sudo systemctl restart open-webui
```

Verify:

```bash
curl -s http://127.0.0.1:11434/api/tags | jq          # Ollama responds
curl -s http://127.0.0.1:11434/api/ps   | jq          # 2 models warm
xdg-open http://127.0.0.1:8080                        # Open WebUI loads
```

## Hardware tuning rationale

These are the load-bearing choices in [ollama.service.d-override.conf](ollama.service.d-override.conf) — change them only with a benchmark to back the change up.

| Setting | Value | Why |
|---|---|---|
| (thread count) | auto (= 8) | **There is no `OLLAMA_NUM_THREADS` env var.** Ollama auto-detects from the active CPU set; `CPUAffinity=0-7` below caps it at 8. To force a per-request value, use the API `options.num_thread` field or a Modelfile `PARAMETER num_thread N`. The `tune-threads.sh` script in this folder sweeps that per-request value. |
| `OLLAMA_NUM_PARALLEL` | 2 | Max concurrent in-flight requests. Higher trades latency for throughput; 2 is conservative for a 2–5 user team. |
| `OLLAMA_MAX_LOADED_MODELS` | 2 | Two warm models cover most chat traffic. Others swap in on demand and stay warm for `OLLAMA_KEEP_ALIVE`. |
| `OLLAMA_KEEP_ALIVE` | 30m | Long enough to avoid reload churn between user sessions, short enough to free RAM eventually. The warmup unit pins its 2 preloaded models for 1440m (24h) which overrides this for those specific models. |
| `OLLAMA_KV_CACHE_TYPE` | q4_0 | ~75% KV-cache RAM savings vs f16 with negligible quality loss. Requires Flash Attention. |
| `OLLAMA_FLASH_ATTENTION` | true | Required for quantized KV cache; modest win on its own. |
| `CPUAffinity` | 0-7 | Constrain inference to 8 of 16 logical CPUs. Under WSL2 the P/E hybrid topology is hidden from Linux, so this is a hint to Windows; whether it actually maps to P-cores depends on the Windows hybrid scheduler. Verify with `lscpu --extended` after hardware changes. |

For Open WebUI ([open-webui.service](open-webui.service)): `WEBUI_WORKERS=2`, `WEBUI_CONCURRENCY=8`, `THREAD_POOL_SIZE=16`. The WebUI is a thin FastAPI front end — the inference bottleneck is Ollama, not these workers. Oversizing wastes RAM.

### Why the model and warm set matter more than the env vars

Empirically on this host, **default model choice and web-search verbosity dominate response time** for chat-with-search workloads. A 2-minute response is almost always a long prefill from injected retrieved content, not slow decode. Specifically:

- **`DEFAULT_MODEL=mistral:7b`** in [open-webui.service](open-webui.service). 3B models are fast but unreliable for RAG over current events — they often answer "no information" even with retrieved context. 7B–8B is the floor for usable web-search Q&A on CPU.
- **Warm set** in [ollama-warmup.service](ollama-warmup.service) is `mistral:7b` + `deepseek-r1:8b`. With `OLLAMA_MAX_LOADED_MODELS=2`, that's all that stays resident. `llama3.2:3b` loads on demand if someone selects it explicitly.
- **Open WebUI admin panel settings** (not in the unit; set via the UI at `/admin/settings` → Web Search). The exact field names matter and have shifted across versions; this is for Open WebUI 0.9.x:
  - **`Bypass Web Loader` → ON** — the single most impactful toggle. Stops Open WebUI from fetching the full body of each Tavily result URL and stuffing it into the prompt. Cuts a typical web-search prompt from ~10k tokens to ~1k tokens, which on mistral:7b cuts response time from ~6 minutes to ~30 seconds.
  - **`Bypass Embedding and Retrieval` → ON** — skips the WebUI's attempt to embed and rerank retrieved content before sending to the LLM. Our unit has `RAG_EMBEDDING_MODEL=` blank on purpose (known vectorization bug), and this toggle ensures the WebUI honors that.
  - `Search Result Count` → 3 is fine; lower to 1–2 only if every second matters.
  - `Fetch URL Content Length Limit` → irrelevant if Bypass Web Loader is ON. If you ever turn the loader back on, cap at ~4000 chars (~1000 tokens) so any single page can't dominate the prompt.

The `ENABLE_RAG_WEB_LOADER=false` env var in [open-webui.service](open-webui.service) is meant to disable full-page fetching, but Open WebUI's env-var → admin-panel semantics have shifted across versions; **verify the toggles in the admin panel** rather than trusting the env var alone. Admin panel settings are persisted in `/var/lib/open-webui/webui.db` and survive restarts.

### How web search is invoked

Open WebUI does NOT auto-search every query. Web search is **per-message**: in the chat composer, click the **globe icon** next to the message input before sending. The globe lights up to indicate search is on for that message. Without the toggle, the model answers from its training data only (which is why a 3B model answered "no information" for a current event — no web context was retrieved).

## Tune empirically

For per-request thread count, run the sweep (it writes a Modelfile parameter or per-request option — read the script before relying on it):

```bash
sudo ./tune-threads.sh                              # default sweep against llama3.2:3b
sudo MODEL=mistral:7b ./tune-threads.sh             # try the new default
```

Re-run after any of: CPU change, kernel upgrade that touches the scheduler, switching the warm model set, or a major Ollama version bump. Caveat: under WSL2 the P/E topology is hidden, so results may not match what the same sweep would produce on bare-metal Linux.

## Rollback to Docker

If something is wrong with the native setup:

```bash
sudo ./uninstall.sh
cd ../docker-swarm && ./start_stack.sh
```

`uninstall.sh` leaves `/var/lib/ollama/`, `/var/lib/open-webui/`, and `/etc/default/open-webui` in place so you can re-install later without losing chats or models.

## Files in this folder

| File | Purpose |
|---|---|
| [ollama.service.d-override.conf](ollama.service.d-override.conf) | Drop-in override (env vars + CPUAffinity) for the upstream `ollama.service`. |
| [open-webui.service](open-webui.service) | Full systemd unit for Open WebUI running from the venv at `/opt/open-webui/venv`. |
| [open-webui.env.example](open-webui.env.example) | Template for `/etc/default/open-webui` — fill in secrets here, never in the unit file. |
| [ollama-warmup.service](ollama-warmup.service) | Oneshot that preloads 3 warm models after Ollama is up. |
| [install.sh](install.sh) | Idempotent installer: prereq checks, dir creation, copies files into place, daemon-reload, restart units. |
| [uninstall.sh](uninstall.sh) | Reverses `install.sh`. Preserves user data. |
| [tune-threads.sh](tune-threads.sh) | Benchmark sweep for per-request thread count. |
| [MIGRATION.md](MIGRATION.md) | Step-by-step from the Swarm stack to this setup (data preservation, sequencing). |
| [patches/tavily.py](patches/tavily.py) | Patched Tavily client (vendor-file override — see below). |
| [patches/apply-tavily-patch.sh](patches/apply-tavily-patch.sh) | Re-applies the Tavily patch after a `pip install -U open-webui`. |

## Web search tuning (Tavily + Open WebUI 0.9.x)

This is the part of the configuration that took the most iteration to get right. Read this before changing anything web-search-related.

### Final working config (as of 2026-05-27, ~1m50s response, accurate)

| Layer | Setting | Value | Why |
|---|---|---|---|
| Chat default model | `DEFAULT_MODEL` env in [open-webui.service](open-webui.service) | `llama3.2:3b` | Bake-off vs mistral:7b: equal accuracy, 2× faster (44 tok/s prefill, 12 tok/s decode). |
| Task default model | `task.model.default` in webui.db config | `llama3.2:3b` | Open WebUI fires up to 6 LLM calls per chat (query gen, retrieval gen, title, tags, follow_up, main). Routing tasks to the small fast 3B model keeps each one sub-second. |
| Warm model count | `OLLAMA_MAX_LOADED_MODELS` in override | **3** | Chat + reasoning + task = 3 distinct models. With only 2 slots a task call against llama3.2:3b would evict the chat model and force a reload. |
| Warm models | [ollama-warmup.service](ollama-warmup.service) | `mistral:7b`, `deepseek-r1:8b`, `llama3.2:3b` | All three pinned with `--keepalive 1440m`. |
| Function-calling mode | `models.default_params.function_calling` in webui.db | `default` (NOT `native`) | `native` makes Open WebUI pass a 27-tool blob (~8000 tokens) on every chat. Small CPU models can't reliably emit the right tool-call schema; the model just outputs malformed JSON and Open WebUI doesn't execute it. `default` makes Open WebUI pre-fetch search results and inject them into the prompt instead. |
| Builtin tools blob | `models.default_metadata.capabilities.builtin_tools` | `false` | Belt-and-suspenders against the function-calling trap above. |
| Tags / follow-up / title | `task.tags.enable`, `task.follow_up.enable`, `task.title.enable` | all `false` | Each fires an extra LLM call after the main response that the user has to wait for. Saves ~12-25s per chat. |
| Search query rewrite | `task.query.search.enable`, `task.query.retrieval.enable` | both `true` | **Cannot disable** — Open WebUI's `chat_web_search_handler` throws HTTP 400 when off (we tried). The query rewrite IS the entire web search flow. Just route it to the fast task model and live with the ~10s cost. |
| Tavily result count | `rag.web.search.result_count` (admin panel: "Search Result Count") | **2** | Each query × 2 results × 3 queries = 6 sources before dedupe. Going from 3 → 2 cut ~15s off the main response time. |
| Tavily params | (vendored patch — see below) | `topic=news, days=3, include_answer=true` | `topic=news` + `days=3` makes Tavily return ONLY dated articles from the last 72h. With `topic=general` the `days` param is silently ignored. `include_answer=true` makes Tavily synthesize a current-state summary which we prepend as a citable `[1]` source. Avoid `search_depth=advanced`: it returns 8× larger snippet payloads which on CPU inference adds 1-2 minutes of prefill. |
| Bypass Web Loader | admin panel toggle (`rag.web.search.bypass_web_loader`) | **ON** | Skips fetching the full body of each result URL. Without this Open WebUI injects ~10-15k tokens of page content per chat. |
| Bypass Embedding and Retrieval | admin panel toggle (`rag.web.search.bypass_embedding_and_retrieval`) | **ON** | Skips RAG embedding/reranking. We disable RAG embedding entirely (see Open WebUI vectorization bug below), so this just makes that an explicit no-op. |

### Vendor patch to Tavily client

Open WebUI's stock Tavily client (`open_webui/retrieval/web/tavily.py` in the venv) sends only `query` and `max_results`. We patch it to also send `topic`, `days`, `include_answer`, and to prepend Tavily's synthesized `answer` field as the first SearchResult.

Source of truth in this repo: [patches/tavily.py](patches/tavily.py). To install / re-apply after an upgrade:

```bash
sudo systemd/patches/apply-tavily-patch.sh
```

The script is idempotent (skips if the destination already matches) and backs up the destination before overwriting. **Re-run this after every `pip install -U open-webui` in `/opt/open-webui/venv`** — `pip` will overwrite the vendor copy.

### Admin panel checklist (Settings → Web Search)

Verify these toggles in the UI at `http://127.0.0.1:8080/admin/settings`:

- Web Search Engine: **tavily**
- Tavily API Key: filled in (matches `/etc/default/open-webui`)
- Search Result Count: **2**
- Bypass Embedding and Retrieval: **ON**
- Bypass Web Loader: **ON**

These persist in `/var/lib/open-webui/webui.db`. They're worth re-checking after any major Open WebUI upgrade.

### How web search is invoked

Web search is **per-message**: click the **globe icon** in the chat composer before sending. It does NOT auto-search every query. Without the toggle, the model answers from training data only (which is how we got "no information" responses in early testing).

## Operating the stack

```bash
# Status
sudo systemctl status ollama ollama-warmup open-webui

# Logs (follow)
sudo journalctl -u ollama -f
sudo journalctl -u open-webui -f

# Restart everything
sudo systemctl restart ollama ollama-warmup open-webui

# Confirm override is applied
sudo systemctl cat ollama | grep -E '^(Environment|CPUAffinity)'

# Disable & Stop the Ollama stack (leave installed)
sudo systemctl disable ollama ollama-warmup open-webui
sudo systemctl stop ollama ollama-warmup open-webui

# Enable & Start the Ollama stack
sudo systemctl enable ollama ollama-warmup open-webui
sudo systemctl start ollama ollama-warmup open-webui
```

## Known issues / open questions

- The legacy config references `qwen3.5:9b` which does not appear in Ollama's public catalog (the qwen family is `qwen2.5:*`, `qwen3:*`). [ollama-warmup.service](ollama-warmup.service) does not preload it; if you want a third warm model, run `ollama list` to find the real tag and add an `ExecStart=` line.
- Open WebUI's signing keys are intentionally not set, so user sessions invalidate on restart. To make them persistent, generate keys with `openssl rand -hex 32` and add `SECRET_KEY=`, `JWT_SECRET_KEY=`, `WEB_SECRET_KEY=` to `/etc/default/open-webui`.
- `CPUAffinity=0-7` is hardware-specific. If you ever run this on a non-hybrid CPU, remove the line entirely (it's a no-op pessimization there).
