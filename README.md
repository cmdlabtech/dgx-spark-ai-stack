# NVIDIA DGX: At-Home AI Stack

A complete self-hosted AI server stack running on the **Nvidia DGX Spark** (arm64/aarch64).

Covers model serving, proxying, workflow automation, an autonomous agent layer, and multi-client access — everything needed to replicate the stack from scratch on a fresh machine.

## Stack

| Component | Role | Port |
|---|---|---|
| [vLLM](https://github.com/vllm-project/vllm) | Model serving | 8000 (internal) |
| [LiteLLM](https://github.com/BerriAI/litellm) | Proxy, logging, routing | 8001 |
| [n8n](https://github.com/n8n-io/n8n) | Workflow automation | 5678 |
| [Hermes Agent](https://github.com/NousResearch/hermes-agent) | Autonomous agent layer | — |
| [Hermes WebUI](https://github.com/nesquena/hermes-webui) | Agent browser UI | 8787 |
| [Open WebUI](https://github.com/open-webui/open-webui) | Daily chat interface | Mac/desktop app |
| Telegram | Mobile/remote access | via Hermes gateway |
| Cline (VS Code) | Agentic coding | VS Code extension |

**Model:** `Qwen/Qwen3.6-35B-A3B-FP8`

## Hardware

- Nvidia DGX Spark (Grace CPU · GB10 GPU · arm64)
- Ubuntu 24.04
- GPU memory utilization: 0.8

## Architecture

```
Users
  ├── Open WebUI (Mac app)
  ├── Cline (VS Code)
  ├── n8n (workflows)
  └── Telegram ──────────────► Hermes Agent ──► Hermes WebUI
        │                           │
        ▼                           ▼
    LiteLLM proxy ◄─────────────────┘
    (port 8001, logs all requests to SQLite)
        │
        ▼
    vLLM (port 8000)
        │
        ▼
    Qwen3.6-35B-A3B-FP8
    Nvidia DGX Spark
```

## Setup guide

The full step-by-step setup guide is in [`index.html`](index.html).


Or open `index.html` directly in any browser — it's a single self-contained file with no external dependencies beyond Google Fonts.

## What the guide covers

1. vLLM container setup with all flags documented
2. Stack directory structure
3. LiteLLM config and systemd service
4. Docker Compose for n8n and Hermes WebUI
5. Hermes Agent install, wizard answers, tool selection, Telegram gateway
6. Open WebUI and Cline configuration
7. Reboot test and service verification
8. Port reference, file locations, backup targets
9. Known issues and fixes (CUDA cache, arm64 quirks, Signal limitations)

## Notes

- All commands use placeholder values (`YOUR_USERNAME`, `YOUR_SERVER_IP`) — substitute your own before running
- LiteLLM has no arm64 Docker image as of May 2026 — installed via pip directly on the host
- Signal is not supported on arm64 due to Java 25 requirements and server-side IP blocking — use Telegram
- The SQLite logs accumulated by LiteLLM (`~/sparky-ai-stack/logs/litellm.db`) serve as a fine-tuning corpus over time

## Container-to-host connectivity

Containers running in Docker cannot reach host-bound services via `localhost` — `localhost` inside a container resolves to the container's own loopback interface, not the host's.

The `extra_hosts: - "host.docker.internal:host-gateway"` entry in `docker-compose.yml` maps the `host.docker.internal` hostname to the Docker bridge gateway address at container start time. Without this explicit mapping, `host.docker.internal` may resolve to the machine's LAN IP instead of the bridge gateway — which silently fails because the host's listening socket is bound to `0.0.0.0` or `127.0.0.1`, neither of which is reachable from the bridge subnet via the LAN IP.

### Service endpoints from inside containers

| Service | Host port | URL from inside a container |
|---|---|---|
| LiteLLM proxy | 8001 | `http://host.docker.internal:8001` |
| vLLM | 8000 | `http://host.docker.internal:8000` |

### Hermes config

`~/.hermes/config.yaml` must use the bridge-reachable URL, not `localhost`:

```yaml
base_url: http://host.docker.internal:8001/v1
```

### Verification

```bash
docker exec hermes-webui curl -s http://host.docker.internal:8001/v1/models
```

A JSON list of available models confirms the container can reach the LiteLLM proxy on the host. A `Connection refused` error means either the `host-gateway` mapping is missing or LiteLLM is not running on the host.

## License

MIT — see [LICENSE](LICENSE)
