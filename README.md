# NVIDIA DGX: At-Home AI Stack — two-node clustered

A self-hosted AI server stack running across **two clustered Nvidia DGX Spark** nodes (arm64/aarch64). vLLM serves the model with tensor parallelism (TP=2) over Ray on a dedicated 200&nbsp;Gb/s direct-attach copper interconnect. Backend services are isolated on one node so user-facing UIs never disturb model latency.

Covers model serving across two nodes, proxying, workflow automation, an autonomous agent layer, and multi-client access — everything needed to replicate the cluster from scratch.

## Setup guide

The full step-by-step setup guide is at [cmdlabtech.github.io/dgx-spark-ai-stack](https://cmdlabtech.github.io/dgx-spark-ai-stack/).

## Architecture summary

Two physically separate DGX Spark nodes, separated by role:

- **`sparky-01` — backend node.** vLLM head (Ray master) + LiteLLM proxy. No user-facing services. Protects inference latency from UI workloads.
- **`sparky-02` — frontend node.** vLLM Ray worker, Open WebUI, Hermes Agent, n8n. All user traffic enters here.

The two nodes are linked by a 200&nbsp;Gb/s DAC interconnect (`enp1s0f0np0`, MTU 9216, point-to-point /30) which carries NCCL collectives for tensor parallelism and Ray control traffic. A separate 1&nbsp;GbE mgmt LAN carries client traffic and the LiteLLM-to-frontend hop.

vLLM is the only clustered service. Open WebUI and n8n run as single instances on `sparky-02` — clustered HA modes are documented in the appendix only.

## Stack

| Component | Node | Role | Port |
|---|---|---|---|
| [vLLM](https://github.com/vllm-project/vllm) head (Ray master) | `sparky-01` | Model serving — TP=2 over Ray on DAC | 8000 (local) · 6379 (Ray GCS) |
| [vLLM](https://github.com/vllm-project/vllm) worker (Ray) | `sparky-02` | Second TP rank | — (joins via DAC) |
| [LiteLLM](https://github.com/BerriAI/litellm) | `sparky-01` | Proxy, logging, routing | 8001 |
| [Open WebUI](https://github.com/open-webui/open-webui) | `sparky-02` | Daily chat interface | 8080 |
| [Hermes Agent](https://github.com/NousResearch/hermes-agent) | `sparky-02` | Autonomous agent layer | — |
| [Hermes WebUI](https://github.com/nesquena/hermes-webui) | `sparky-02` | Agent browser UI | 8787 |
| [n8n](https://github.com/n8n-io/n8n) | `sparky-02` | Workflow automation | 5678 |
| Telegram gateway | `sparky-02` | Mobile/remote access | via Hermes |
| Syncthing | Proxmox LXC | Vault sync (optional) | 8384 |
| obsidian-mcp + supergateway | Proxmox LXC | Vault tool exposure to LiteLLM | 3000 |

**Default model:** `Qwen/Qwen3.6-35B-A3B-FP8` (FP8 MoE, ~97 GB resident per node at `--gpu-memory-utilization 0.80`).

**Optional upgrade:** `Qwen/Qwen3.5-122B-A10B-GPTQ-Int4` — fits comfortably in clustered memory at INT4 (~30 GB per node).

## Hardware

- 2× Nvidia DGX Spark (Grace CPU · GB10 GPU · arm64) — Ubuntu 24.04
- DAC interconnect: `enp1s0f0np0`, MTU 9216, /30 between nodes
- Mgmt LAN: 1 GbE RJ45, default routes
- Proxmox LXC (optional) — `[YOUR-CONTAINER-HOSTNAME]` (Ubuntu 24.04 LTS) for Syncthing vault sync

## Architecture diagram

```
                      ┌──────────────────────┐
                      │  Users / clients     │
                      │  browser · Telegram  │
                      │  desktop · VS Code   │
                      └──────────┬───────────┘
                                 │ mgmt LAN
                                 ▼
┌────────────────────────────────────────────────────────────┐
│  sparky-02 · FRONTEND NODE   (mgmt: YOUR_NODE2_MGMT_IP)    │
│                                                            │
│  Open WebUI (8080)   n8n (5678)   Hermes Agent / WebUI     │
│         │                │                 │               │
│         └───────┬────────┴─────────────────┘               │
│                 │                                          │
│                 │  http://YOUR_NODE1_MGMT_IP:8001/v1       │
│                 ▼                                          │
│        ┌────────────────────────────┐                      │
│        │  vLLM worker (Ray)         │◄────┐                │
│        │  GPU 1 of TP=2             │     │ NCCL · Ray     │
│        └────────────────────────────┘     │ over DAC       │
│                                           │ enp1s0f0np0    │
└───────────────────────────────────────────┼────────────────┘
                                            │ 200 Gb/s
┌───────────────────────────────────────────┼────────────────┐
│  sparky-01 · BACKEND NODE    (mgmt: YOUR_NODE1_MGMT_IP)    │
│                                           │                │
│        ┌──────────────────────────────────┴───┐            │
│        │  vLLM head (Ray master)              │            │
│        │  --tensor-parallel-size 2 · GPU 0    │            │
│        └────────────────┬─────────────────────┘            │
│                         │                                  │
│                         ▼                                  │
│        ┌─────────────────────────────────────┐             │
│        │  LiteLLM proxy (8001)               │             │
│        │  → localhost:8000                   │             │
│        └─────────────────────────────────────┘             │
│                         │                                  │
│                         ▼                                  │
│        ┌─────────────────────────────────────┐             │
│        │  Qwen/Qwen3.6-35B-A3B-FP8           │             │
│        └─────────────────────────────────────┘             │
└────────────────────────────────────────────────────────────┘
```

## Obsidian Vault Sync & MCP Integration

A self-hosted Obsidian vault sync and AI query pipeline using Syncthing for bidirectional vault sync and `obsidian-mcp` for vault tool exposure to LiteLLM.

### Components

**Proxmox LXC — `[YOUR-CONTAINER-HOSTNAME]` (Ubuntu 24.04 LTS, IP `[YOUR-LXC-IP]`, VLAN `[YOUR-VLAN-ID]`)**

- Syncthing running as a systemd service (`syncthing@root`), vault lives at `/vault/`
- `/vault/.obsidian/app.json` — required stub (contains `{}`) for `obsidian-mcp` vault validation
- `obsidian-mcp` (StevenStavrakis, v1.0.6) — exposes vault contents to LiteLLM as a callable tool
- `supergateway` — wraps `obsidian-mcp` with `streamableHttp` transport on port `3000`; both run under a single `obsidian-mcp` systemd service
- No Tailscale on the LXC — client devices use Tailscale when traveling to tunnel back to the home network

**Desktop Client + Mobile Client** — Obsidian with Syncthing installed on both; all devices sync bidirectionally to the Syncthing instance on the LXC.

**LiteLLM (`[YOUR-AI-SERVER-HOSTNAME]`)** — MCP server config pointing at `http://[YOUR-LXC-IP]:3000/mcp` with `http` transport. This enables any LiteLLM client (Telegram, Hermes, n8n, Open WebUI) to query vault notes as a tool call.

### Key configuration

| Setting | Value |
|---|---|
| Syncthing GUI | `0.0.0.0:8384` (patched from default `127.0.0.1`) |
| Vault path on LXC | `/vault/` |
| Vault stub | `/vault/.obsidian/app.json` → `{}` |
| MCP server | `obsidian-mcp` v1.0.6 (StevenStavrakis) |
| MCP transport | `streamableHttp` via `supergateway`, port `3000` |
| MCP endpoint | `http://[YOUR-LXC-IP]:3000/mcp` |
| Node.js version | 22 (v18 segfaults; v20+ required) |
| Auth | None — internal VLAN only |

### Services

| Service | Command | Port |
|---|---|---|
| Syncthing | `systemctl status syncthing@root` | `8384` |
| Obsidian MCP | `systemctl status obsidian-mcp` | `3000` |

### LiteLLM MCP Configuration

| Field | Value |
|---|---|
| MCP Server URL | `http://[YOUR-LXC-IP]:3000/mcp` |
| Transport | `http` |
| Auth | None |

### Bugs and fixes encountered

**1. Syncthing config path changed** — On Ubuntu 24.04, config is at `/root/.local/state/syncthing/config.xml`, not `/root/.local/share/syncthing/config.xml` as documented elsewhere.

**2. obsidian-mcp vault validation** — `obsidian-mcp` requires a `.obsidian` directory with `app.json` to consider a directory a valid vault. An empty directory fails with `Error: Not a valid Obsidian vault`.

**3. SSE transport incompatible with LiteLLM v1.80.18+** — LiteLLM's MCP client uses protocol version `2025-11-25` which causes `Connection closed` errors with supergateway's SSE transport. Fix: use `--outputTransport streamableHttp` and set transport to `http` in LiteLLM UI.

**4. LXC disk corruption on network-backed storage** — Storing the LXC root disk on a network share (e.g. CIFS/SMB) caused EXT4 I/O errors and disk corruption under write load. Fix: use local storage or a reliable block storage backend for LXC root disks.

**5. Syncthing folder path special characters** — Copying a folder path from a file manager may add escape characters. Set the Syncthing folder path manually in the config UI instead of pasting from the file manager.

### Why the LXC, not the AI server

Deploying Syncthing and the MCP pipeline on a separate Proxmox LXC rather than on the AI server itself keeps inference RAM available for model serving. The AI server's RAM is fully committed at idle — anything that requires a resident daemon competes directly with model weights. The LXC is lightweight, always-on, and isolated from the inference stack.

---

### Why vLLM runs outside Docker Compose

vLLM is started with standalone `docker run` commands on each node (driven by per-node startup scripts in `~/sparky-ai-stack/scripts/`) rather than being declared as a service in any Compose file. This is intentional. Loading a 35B FP8 model across two nodes takes several minutes and saturates GPU memory on both nodes for the duration — restarting the cluster is expensive. Keeping it outside Compose means:

- `docker compose up/down/restart` on n8n or hermes-webui has zero effect on the vLLM cluster
- Iterating on workflow automation, the agent UI, or compose config doesn't force a model reload on either node
- vLLM can be updated or restarted independently — the launch order (worker first, then head) is enforced explicitly by the scripts
- A crash or misconfiguration in a compose service can't cascade into taking down the model server

In practice this means the vLLM cluster runs continuously and is only restarted deliberately (e.g. to pick up a new model or change serving flags), while everything above it in the stack is free to cycle as often as needed.

## What the guide covers

1. Hardware topology and prerequisites — `/etc/hosts` mgmt-IP entries, docker group, passwordless SSH between nodes
2. vLLM clustered (TP=2 over Ray on DAC) — custom `vllm-spark:26.04` image build on both nodes, HF cache rsync, per-node startup scripts, launch order, NCCL/`VLLM_HOST_IP` configuration, Ray cluster verification
3. LiteLLM proxy on `sparky-01` — pointing at the local clustered vLLM, systemd service, override.conf cleanup
4. Open WebUI on `sparky-02` — single instance, points at LiteLLM on `sparky-01`
5. Hermes Agent + Telegram gateway on `sparky-02` — wizard answers, base URL pointing at LiteLLM on `sparky-01`
6. n8n on `sparky-02` — single instance, persistent Docker volume
7. Validation checklist (per-node) and end-to-end Telegram → Hermes → LiteLLM → vLLM TP=2 round-trip
8. Cluster issues and resolutions: Ray GCS connection, `VLLM_HOST_IP` mismatch, NCCL on wrong interface, worker-before-head, `nvidia-smi memory.used [N/A]` on GB10
9. Obsidian vault sync integration — Syncthing, obsidian-mcp, supergateway (Proxmox LXC)
10. Brave Search MCP and Playwright MCP setup
11. Appendix — clustered Open WebUI / n8n HA notes for those who want to pursue it

## Notes

- All commands use placeholder values (`YOUR_USERNAME`, `YOUR_NODE1_MGMT_IP`, `YOUR_NODE2_MGMT_IP`, `YOUR_NODE1_DAC_IP`, `YOUR_NODE2_DAC_IP`) — substitute your own before running. Hostnames `sparky-01` and `sparky-02` are conventional in this guide; substitute your own.
- LiteLLM has no arm64 Docker image as of May 2026 — installed via pip directly on `sparky-01`
- The SQLite logs accumulated by LiteLLM (`~/sparky-ai-stack/logs/litellm.db`) serve as a fine-tuning corpus over time
- vLLM is intentionally run via per-node `docker run` scripts, not as Compose services — this keeps the cluster isolated from compose lifecycle operations so model weights stay loaded across both nodes while the rest of the stack is restarted freely
- `nvidia-smi --query-gpu=memory.used,memory.total` returns `[N/A]` on GB10 (Grace Blackwell unified memory). Use plain `nvidia-smi` and read the Processes section instead.

## Troubleshooting

### Enabling the LiteLLM Admin UI

The LiteLLM proxy ships with a built-in web UI at `http://<host>:8001/ui`. It requires a master key and a PostgreSQL database — SQLite is not supported for the UI auth layer.

**Step 1 — Set a master key**

Add to `~/sparky-ai-stack/litellm-config.yaml` (on `sparky-01`):

```yaml
general_settings:
  master_key: sk-yourkey
  database_url: "postgresql://litellm:litellm@localhost:5432/litellm"
```

Generate a key with:

```bash
echo "sk-$(openssl rand -hex 16)"
```

**Step 2 — Add PostgreSQL on sparky-01**

Run a Postgres container on `sparky-01` (the same node as LiteLLM). Avoid putting it on `sparky-02` — Postgres latency on the inference path defeats the point of backend isolation.

```yaml
  litellm-db:
    image: postgres:16
    container_name: litellm-db
    restart: unless-stopped
    environment:
      - POSTGRES_USER=litellm
      - POSTGRES_PASSWORD=litellm
      - POSTGRES_DB=litellm
    ports:
      - "5432:5432"
    volumes:
      - litellm_db:/var/lib/postgresql/data

volumes:
  litellm_db:
```

```bash
docker compose up -d litellm-db
```

`restart: unless-stopped` combined with `sudo systemctl enable docker` ensures the container survives reboots without a separate systemd unit.

**Step 3 — Install Prisma**

LiteLLM uses Prisma as its ORM. It is not included in the base pip package:

```bash
pip install prisma --break-system-packages
```

`--break-system-packages` bypasses a Python 3.12 restriction on installing into the system environment. It is safe on a dedicated AI server.

**Step 4 — Generate Prisma binaries**

```bash
cd ~/.local/lib/python3.12/site-packages/litellm/proxy
prisma generate --schema schema.prisma
```

**Step 5 — Apply the database schema**

```bash
DATABASE_URL="postgresql://litellm:litellm@localhost:5432/litellm" \
prisma db push --schema schema.prisma
```

`DATABASE_URL` must be passed inline — Prisma reads it directly from the environment, not from `litellm-config.yaml`.

**Step 6 — Restart LiteLLM**

```bash
sudo systemctl daemon-reload
sudo systemctl restart litellm
sudo systemctl status litellm
```

**Errors encountered in order**

| Error | Cause | Fix |
|---|---|---|
| `Authentication Error, Not connected to DB` | No PostgreSQL configured | Add `database_url` to `general_settings` |
| `ModuleNotFoundError: No module named 'prisma'` | Prisma not installed | `pip install prisma --break-system-packages` |
| `Unable to find Prisma binaries` | `prisma generate` not run | Run `prisma generate --schema schema.prisma` |
| `The table 'public.LiteLLM_UserTable' does not exist` | Schema not applied to DB | Run `prisma db push --schema schema.prisma` |

**Accessing the UI**

Navigate to `http://YOUR_NODE1_MGMT_IP:8001/ui`. Username: `admin`. Password: your `master_key` value.

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
