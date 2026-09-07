# NVIDIA DGX: At-Home AI Stack

Self-hosted inference and apps on **two Nvidia DGX Spark** nodes (arm64 / GB10 / Ubuntu 24.04).

This repository documents **two supported layouts**. Keep both. Choose one per deployment; you can switch later.

| | Architecture A — clustered | Architecture B — isolated solo |
|---|---|---|
| vLLM | One process, TP=2 over Ray | One process per node, TP=1 |
| GPU | Shared pool (~256 GB unified) | Each node owns its GB10 |
| Who sees prompts | Head node API sees both UIs | Each node's API sees only its UI |
| Typical models | 122B-class FP8 (cluster-only) or INT4 AutoRound at TP=2 | Node A: dense ~27B FP8. Node B: 122B-class INT4 AutoRound |
| When | One shared model, max context pool | Isolation, independent models, no Ray |

Full walkthrough (clustered steps plus the isolated overview): the GitHub Pages guide in `index.html`.

## Naming in this repo

Documentation uses **node-a** (personal apps + optional Hermes) and **node-b** (workload Open WebUI). Substitute your own hostnames.

Documentation addresses only:

- Management: `192.0.2.21` / `192.0.2.22` (TEST-NET-1)
- DAC example net: `198.51.100.0/30` (TEST-NET-2)

Never publish real management IPs, overlay IPs, usernames, or tailnet names.

## Architecture A — clustered TP=2

Three layers:

1. **Application stacks** — independent Open WebUI, n8n, and (on node-a) Hermes. Separate volumes, keys, and logs.
2. **Direct OpenAI-compatible calls** — each UI talks to vLLM. No required proxy.
3. **Shared compute** — vLLM head on node-a `:8000` (Ray rank 0). Worker on node-b (rank 1, no API listener). NCCL on the DAC.

```
 node-a apps  -->  127.0.0.1:8000
 node-b apps  -->  198.51.100.1:8000   (DAC to head)
                      |
              vLLM TP=2 + Ray
              NCCL on DAC 200 Gb/s
```

Port **8000 must not** be published on any overlay network. It has no auth.

### Trust model (A only)

- The operator of the head process can observe prompts and completions at the API layer. Same profile as any hosted inference API.
- The Ray worker sees tensor activations, not text.
- Application data (knowledge bases, chats, workflows) does not cross nodes.

## Architecture B — isolated solo TP=1

Each node runs `./run-recipe.sh <recipe> --solo -d --tp 1`. No Ray. Cluster unit **disabled on boot** on both nodes so a reboot cannot steal a GPU back into pair mode.

```
 node-a                         node-b
 Open WebUI :8080               Open WebUI :8080
 Hermes :9119                   n8n :5678
 n8n :5678
        \                             \
         vLLM :8000 TP=1               vLLM :8000 TP=1
         example: 27B-class FP8        example: 122B-class INT4
```

Example launch (placeholders only):

```bash
cd "$HOME/spark-vllm-docker"
./run-recipe.sh RECIPE_NAME --solo -d --tp 1 -- \
  --served-model-name SERVED_ID \
  --max-model-len CONTEXT_CAP
```

- Many 122B FP8 recipes are `cluster_only`. Solo on one GB10 uses INT4 AutoRound or a 27B/35B FP8 recipe.
- First solo window: cap `--max-model-len` (32768 on the large INT4 lane is a safe start; 65536 on a 27B lane if the agent requires ≥64k).
- Match `--tool-call-parser` to the chat template (Qwen3.5 tool loops: `qwen3_coder`).
- Open WebUI container: `--add-host=host.docker.internal:host-gateway`. Connections URL: `http://host.docker.internal:8000/v1`.
- Hermes: `base_url` / `api` = `http://localhost:8000/v1`, dummy `api_key` for local vLLM, `model.max_tokens: 8192` (do not let the provider default to a full-window completion). Leave context compression off until first-turn prompts are small.

Unit templates: `templates/vllm-cluster.service` and `templates/vllm-solo.service`.

## Stack (both layouts)

| Component | Typical port | Notes |
|---|---|---|
| vLLM | 8000 | Host network. Never on an overlay. |
| Open WebUI | 8080 | Per-node volume. |
| n8n | 5678 | Compose file in this repo is n8n-only. |
| Hermes gateway / dashboard | 9119 | Native systemd on node-a. Not a Compose service. |
| Ray GCS (A only) | 6379 | Cluster mode. |

vLLM is launched by `eugr/spark-vllm-docker` (`run-recipe.sh`), not Compose. Compose restarts must not reload weights.

## Hardware

- 2× DGX Spark (Grace + GB10, arm64), Ubuntu 24.04
- DAC: 200 Gb/s copper, jumbo frames, example `/30` above
- 1 GbE management for SSH and bootstrap
- Optional: separate overlay network per owner

`nvidia-smi --query-gpu=memory.used` returns N/A on GB10. Use process rows.

## What the Pages guide covers

Architecture A steps stay in `index.html` (vLLM cluster, both Open WebUIs, overlays, Hermes, n8n, validation, issues). Architecture B is the new **Architecture B — isolated solo** section plus this README and `docs/`.

## Housekeeping

- Placeholders only in scripts: `YOUR_USERNAME`, `NODE_A_MGMT_IP`, `NODE_B_DAC_IP`, `YOUR_HF_TOKEN`, served model ids.
- Do not commit Hugging Face caches, `.env` files, Open WebUI volumes, or session transcripts.
- Do not commit real hostnames, tailnet FQDNs, or overlay addresses.
