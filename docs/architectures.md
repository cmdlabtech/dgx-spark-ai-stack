# Architectures

Two layouts. Both stay in-tree. A single Spark is always isolated solo.

Launcher facts (eugr/spark-vllm-docker, 2026-09): default image tag is `vllm-node` (`eugr/spark-vllm:latest`). Do not pass `--tf5`. Multi-node default is no-Ray; `--ray` is opt-in. Weights: `hf-download.sh`.

## A — Clustered (TP=2)

Use when both nodes should contribute to one model.

- Launcher: `run-recipe.sh <cluster-recipe> -d` from the head only
- Systemd: `templates/vllm-cluster.service` on the head only
- Head listens on `:8000`. Worker has no OpenAI listener
- Node-b Open WebUI Connections: DAC address of the head, port 8000
- Node-a Open WebUI Connections: `http://host.docker.internal:8000/v1`
- Typical recipe: `qwen3.5-122b-fp8` (`cluster_only: true`). Supported `--max-model-len`: 262144

Stop sequence: `launch-cluster.sh stop` from the head (stops local container and SSHes the peer). Always `docker rm -f vllm_node` on **both** nodes if a restart skipped head create.

## B — Isolated solo (TP=1)

Use when you have one Spark, when each node should keep serving through the other node's reboot, or when models differ.

- Launcher: `run-recipe.sh <solo-recipe> --solo -d --tp 1 -- --served-model-name ID --max-model-len N`
- Systemd: `templates/vllm-solo.service` on each node that should autostart
- Disable the cluster unit on boot on the former head
- FP8 122B-class files marked `cluster_only: true` cannot be the solo recipe
- Supported windows on one GB10: INT4 122B-class **32768**; 35B FP8 **65536**. Recipe file default 262144 OOMs solo.

### Hermes on node-a (B)

| Setting | Value |
|---|---|
| Provider base URL | `http://localhost:8000/v1` |
| Dummy API key | required by some agent builds even when vLLM ignores it |
| `model.max_tokens` | `8192` (must live under `model:`, not only under a fan-out block) |
| `model.context_length` | match vLLM `--max-model-len` |
| `compression.enabled` | `false` until first-turn prompts are small |

If the custom provider defaults `max_tokens` to the full context window, vLLM returns 400 (output + prompt exceed window). Some agent builds then run context compression even when compression is disabled.

## Switching

A → B: stop cluster, rm containers, launch solo per node, retarget Connections.

B → A: stop both solo units, rm containers, start cluster from the head, retarget node-b Connections to the head DAC IP.

Never run cluster and solo containers named `vllm_node` at the same time.
