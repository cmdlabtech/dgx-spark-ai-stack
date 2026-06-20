# NVIDIA DGX: At-Home AI Stack — split-trust shared compute

A self-hosted AI server stack running across **two clustered Nvidia DGX Spark** nodes (arm64/aarch64) under **split ownership**. vLLM serves a shared model with tensor parallelism (TP=2) over Ray on a 200&nbsp;Gb/s direct-attach copper interconnect, but each node runs its own independent application stack owned by a different party.

`spark-01` is the **owner's** node (your LiteLLM, Open WebUI, Hermes Agent, n8n, Tailscale). `spark-02` is the **client's** node (their LiteLLM, Open WebUI, n8n, Tailscale). Both LiteLLM proxies talk to the same vLLM endpoint on `spark-01:8000` over the DAC; neither application stack sees the other.

> **Read the [Trust model](https://cmdlabtech.github.io/dgx-spark-ai-stack/#trust-model) section before deploying.** This architecture has specific properties at the API layer that you should understand explicitly.

## Setup guide

The full step-by-step setup guide is at [cmdlabtech.github.io/dgx-spark-ai-stack](https://cmdlabtech.github.io/dgx-spark-ai-stack/).

## Architecture summary

Three logical layers:

1. **Application stacks (separate ownership).** Two independent stacks on two nodes — your apps on `spark-01`, client's apps on `spark-02`. Knowledge bases, chat history, RAG pipelines, API keys, and logs are completely separate. Neither party has access to the other's stack.
2. **LiteLLM proxies (one per side).** Each side runs its own LiteLLM with its own master key and its own SQLite log corpus. Your LiteLLM uses `api_base = http://localhost:8000/v1`; client's LiteLLM uses `api_base = http://198.51.100.1:8000/v1` over the DAC.
3. **Shared compute pool.** vLLM head (Ray master, TP rank 0) runs on `spark-01:8000` backed by the full 256 GB unified memory across both nodes. The Ray worker on `spark-02` (TP rank 1) processes tensor activations only — no readable text crosses the worker.

Tailscale is a per-owner overlay: each node joins its owner's tailnet independently, with separate ACL policies. The DAC link (`198.51.100.0/30`) is private physical hardware between the two nodes — not routed through either tailnet.

## Trust model

- **API-layer visibility.** The owner of `spark-01` runs the vLLM API server; both LiteLLM proxies call it. Trust profile is structurally identical to using any commercial hosted-inference API (OpenAI, Anthropic, Together, etc.) — the entity running the API server can see traffic at the API layer.
- **Tensor-layer isolation.** The Ray worker on `spark-02` processes floating-point tensor activations, not text. NCCL allreduce on the DAC carries floats, not strings. The client's node never sees readable prompts or completions at the compute layer.
- **Application-layer isolation.** Knowledge bases, chat history, RAG indexes, vector stores, OAuth tokens, and request logs are 100% separate per node. No cross-mounted volumes, no shared Postgres, no shared file system.
- **Network isolation.** Two separate tailnets. ACLs per owner. DAC is private hardware, not advertised on either tailnet.
- **Appropriate when:** both parties have a working relationship; data is non-regulated; trust profile of "any hosted inference API" is acceptable.
- **Requires additional agreements when:** either party handles regulated data (HIPAA, GDPR, SOC2, PCI-DSS, attorney-client privileged) or has contractual data-handling requirements imposed by their own customers.

## Stack

| Component | Node | Owner | Port |
|---|---|---|---|
| [vLLM](https://github.com/vllm-project/vllm) head (Ray master, TP rank 0) | `spark-01` | Shared compute | 8000 (local + DAC) · 6379 |
| [vLLM](https://github.com/vllm-project/vllm) worker (Ray, TP rank 1) | `spark-02` | Shared compute | — (no API listener) |
| Your [LiteLLM](https://github.com/BerriAI/litellm) | `spark-01` | You — your master key, your logs | 8001 (your tailnet) |
| Client [LiteLLM](https://github.com/BerriAI/litellm) | `spark-02` | Client — their master key, their logs | 8001 (client's tailnet) |
| Your [Open WebUI](https://github.com/open-webui/open-webui) | `spark-01` | You — your data | 8080 (your tailnet) |
| Client [Open WebUI](https://github.com/open-webui/open-webui) | `spark-02` | Client — their data | 8080 (client's tailnet) |
| Your [Hermes Agent](https://github.com/NousResearch/hermes-agent) | `spark-01` | You | — |
| Your Hermes dashboard (built-in) | `spark-01` | You | 9119 (your tailnet) |
| Your [n8n](https://github.com/n8n-io/n8n) | `spark-01` | You | 5678 (your tailnet) |
| Client [n8n](https://github.com/n8n-io/n8n) | `spark-02` | Client | 5678 (client's tailnet) |
| Your Tailscale | `spark-01` | You — your ACLs | — |
| Client Tailscale | `spark-02` | Client — their ACLs | — |
| Telegram gateway (Hermes) | `spark-01` | You | — |

**Production model:** `Intel/Qwen3.5-122B-A10B-int4-AutoRound` (122B / A10B MoE, INT4 via Intel AutoRound; ~37 GB resident per node, leaving ~91 GB per-node for KV cache). Steady-state throughput ~45 tok/s at TP=2 with NCCL over RoCE/RDMA on the DAC. MTP speculative decoding is disabled — unstable in vLLM v0.19.0 on Qwen3.5-class models. 262K context.

**Bootstrap fallback:** `Qwen/Qwen3.6-35B-A3B-FP8` — the model used to bring the cluster up the first time; useful for fast iteration on Ray/NCCL/RoCE wiring before committing to the longer 122B load.

**Tested but does not fit / not supported:** `Qwen/Qwen3-235B-A22B-FP8` (at ~117.5 GB/node FP8 there is no room for KV cache; Ray OOMs the worker) and `Sehyo/Qwen3.5-122B-A10B-NVFP4` (NVFP4 is currently single-node only on DGX Spark — multi-node fails at cluster launch).

## Hardware

- 2× Nvidia DGX Spark (Grace CPU · GB10 GPU · arm64) — Ubuntu 24.04
- DAC interconnect: `enp1s0f0np0`, MTU 9216, /30 between nodes — private physical link, not routed
- Mgmt LAN: 1 GbE RJ45, default routes — for SSH and bootstrap
- Two independent Tailscale tailnets — one per owner, with independent ACL policies
- Proxmox LXC (optional, on owner side) — `[YOUR-CONTAINER-HOSTNAME]` (Ubuntu 24.04 LTS) for Syncthing vault sync

## Architecture diagram

```
       Your users                                     Client's users
       (your tailnet)                                 (client's tailnet)
            │                                                │
            ▼                                                ▼
┌──────────────────────────────┐          ┌──────────────────────────────┐
│ spark-01 — YOUR NODE         │          │ spark-02 — CLIENT NODE       │
│ (your tailscale)             │          │ (client's tailscale)         │
│                              │          │                              │
│  Your Open WebUI    :8080    │          │  Client Open WebUI    :8080  │
│  Your n8n           :5678    │          │  Client n8n           :5678  │
│  Your Hermes        :9119    │          │                              │
│            │                 │          │            │                 │
│            ▼                 │          │            ▼                 │
│  Your LiteLLM       :8001    │          │  Client LiteLLM      :8001   │
│  api_base=localhost:8000     │          │  api_base=198.51.100.1:8000  │
└──────────┬───────────────────┘          └──────────┬───────────────────┘
           │                                         │
           │ localhost                               │ DAC (200 Gb/s)
           ▼                                         ▼
┌────────────────────────────────────────────────────────────────────┐
│ SHARED COMPUTE POOL                                                │
│                                                                    │
│   vLLM head (Ray master) :8000  · TP rank 0 · spark-01             │
│   vLLM Ray worker               · TP rank 1 · spark-02             │
│                                                                    │
│   Intel/Qwen3.5-122B-A10B-int4-AutoRound — 256 GB unified memory   │
│                                                                    │
│   NCCL allreduce on DAC: RoCE/RDMA · rocep1s0f0,roceP2p1s0f0       │
│   ↑ NCCL_IB_HCA pinned to both RoCE twins · MTU 9216 · /30 ↑       │
│   ↑ private physical hardware · NOT routed through any tailnet ↑   │
└────────────────────────────────────────────────────────────────────┘
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

vLLM is started by the `eugr/spark-vllm-docker` launcher (`./run-recipe.sh`) — fronted by a `vllm-cluster.service` systemd unit on `spark-01` — rather than as a service in any Compose file. This is intentional. Loading the 122B AutoRound INT4 model across two nodes takes several minutes and pins ~37 GB of weights resident on each node — restarting the cluster is not cheap. Keeping it outside Compose means:

- `docker compose up/down/restart` on n8n or open-webui has zero effect on the vLLM cluster
- Iterating on workflow automation, the agent UI, or compose config doesn't force a model reload on either node
- vLLM can be updated or restarted independently — the launcher forms the Ray cluster (head, then worker, with a GPU-count gate before `vllm serve`) and propagates `NCCL_IB_HCA` / `/dev/infiniband` passthrough into both containers
- A crash or misconfiguration in a compose service can't cascade into taking down the model server

In practice this means the vLLM cluster runs continuously and is only restarted deliberately (e.g. to pick up a new model or change serving flags), while everything above it in the stack is free to cycle as often as needed.

## What the guide covers

1. Hardware topology + Trust model + prerequisites — `/etc/hosts`, docker group, passwordless SSH between nodes
2. **Step 01 — vLLM clustered (TP=2 over Ray on RoCE/RDMA)** — `eugr/spark-vllm-docker` (pre-built SM121a Blackwell wheels) on both nodes, RoCE interface verification, `./build-and-copy.sh --tf5`, autodiscovery, HF cache rsync, `./run-recipe.sh qwen3.5-122b-int4-autoround`, `NCCL_IB_HCA` over `/dev/infiniband`, `systemd vllm-cluster.service`, performance results (~45 tok/s vs the old 2–3 tok/s), GB10 `nvidia-smi` quirk
3. **Step 02 — Your LiteLLM (spark-01)** — your master key, your SQLite log corpus, points at `localhost:8000`
4. **Step 03 — Client LiteLLM (spark-02)** — separate install, separate master key, separate log corpus, points at `198.51.100.1:8000` over the DAC
5. **Step 04 — Your Open WebUI (spark-01)** — points at your LiteLLM, your tailnet
6. **Step 05 — Client Open WebUI (spark-02)** — points at client's LiteLLM, client's tailnet, client's data stays on `spark-02`
7. **Step 06 — Tailscale (both nodes, separate tailnets)** — per-owner ACLs, host firewall rules that prevent the unauthenticated vLLM port leaking onto either tailnet
8. **Step 07 — Your Hermes Agent (spark-01)** — Telegram gateway, built-in dashboard (port 9119), dashboard Node.js build fix, desktop app (v0.15.2), memory limits, dashboard auto-restart on gateway update
9. **Step 08 — Your n8n (spark-01)** — single-instance, owner-side flows. Client deploys their own n8n on `spark-02` independently.
10. Validation checklist — both-side positive tests + cross-stack negative tests (each side cannot reach the other)
11. Cluster issues and resolutions: NCCL falling back to TCP (slow inference), NVFP4 multi-node stall, Ray version mismatch, Ray GCS, `VLLM_HOST_IP` / `LOCAL_IP` mismatch, NCCL on wrong interface, client LiteLLM can't reach vLLM, port-8000 leak through Tailscale ACL, cross-LiteLLM mgmt-LAN collision, log-bleed across owners
12. Obsidian vault sync integration — Syncthing, obsidian-mcp, supergateway (Proxmox LXC, owner side)
13. Brave Search MCP and Playwright MCP setup
14. Appendix — clustered Open WebUI / n8n HA notes for those who want to pursue it

## Notes

- All copy-paste commands use placeholder values (`YOUR_USERNAME`, `YOUR_NODE1_MGMT_IP`, `YOUR_NODE2_MGMT_IP`, `YOUR_NODE1_DAC_IP`, `YOUR_NODE2_DAC_IP`, `YOUR_MASTER_KEY`, `YOUR_CLIENT_MASTER_KEY`, `YOUR_NODE1_TAILSCALE_IP`, `YOUR_NODE2_TAILSCALE_IP`) — substitute your own before running. Hostnames `spark-01` and `spark-02` are conventional; substitute your own.
- **Master keys must be different.** Yours is unique to your LiteLLM on `spark-01`. The client's is unique to their LiteLLM on `spark-02`. They are never shared and never sync'd between nodes.
- **Tailscale ACLs are independent per owner.** Each owner controls their own tailnet's ACL policy. Cross-tailnet exposure happens only if both owners explicitly configure it.
- **Port 8000 (vLLM) must never leak onto either tailnet.** It has no auth. The Step 06 ufw rules are the enforcement; the Tailscale ACLs are the policy. Both must agree.
- **Application-layer data stays per-owner.** Open WebUI knowledge bases, n8n flows, Hermes memory, LiteLLM logs — none of these cross the boundary. Each owner backs up their own node's state.
- LiteLLM has no arm64 Docker image as of May 2026 — installed via pip directly on each node
- vLLM is intentionally run via the `eugr/spark-vllm-docker` launcher and a dedicated `vllm-cluster.service` systemd unit, not as a Compose service — keeps the cluster isolated from compose lifecycle operations and ensures NCCL gets RDMA/RoCE rather than TCP fallback
- `nvidia-smi --query-gpu=memory.used,memory.total` returns `[N/A]` on GB10 (Grace Blackwell unified memory). Use plain `nvidia-smi` and read the Processes section instead.

## Troubleshooting

### Enabling the LiteLLM Admin UI

The LiteLLM proxy ships with a built-in web UI at `http://<host>:8001/ui`. It requires a master key and a PostgreSQL database — SQLite is not supported for the UI auth layer.

**Step 1 — Set a master key**

Add to `~/sparky-ai-stack/litellm-config.yaml` (on `spark-01`):

```yaml
general_settings:
  master_key: sk-yourkey
  database_url: "postgresql://litellm:litellm@localhost:5432/litellm"
```

Generate a key with:

```bash
echo "sk-$(openssl rand -hex 16)"
```

**Step 2 — Add PostgreSQL on spark-01**

Run a Postgres container on `spark-01` (the same node as LiteLLM). Avoid putting it on `spark-02` — Postgres latency on the inference path defeats the point of backend isolation.

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

Hermes itself runs as a systemd service (not in Docker), so `~/.hermes/config.yaml` uses `localhost` directly:

```yaml
base_url: http://localhost:8001/v1
```

Containers that call LiteLLM from inside Docker (n8n, Open WebUI) use `host.docker.internal` instead of `localhost`.

### Verification

```bash
# From host — Hermes → LiteLLM
curl -s http://localhost:8001/v1/models

# From inside n8n or Open WebUI container
docker exec n8n curl -s http://host.docker.internal:8001/v1/models
```

A JSON list of available models confirms connectivity. `Connection refused` means either the `host-gateway` mapping is missing from `docker-compose.yml` or LiteLLM is not running.

## License

MIT — see [LICENSE](LICENSE)
