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

**View it live:** host on GitHub Pages by enabling Pages in your repo settings (source: root, branch: main). The guide will be available at `https://YOUR_USERNAME.github.io/dgx-spark-ai-stack`.

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

## License

MIT — see [LICENSE](LICENSE)
