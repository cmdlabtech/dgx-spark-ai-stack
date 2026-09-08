# NVIDIA DGX: At-Home AI Stack

Self-hosted inference and apps on **one or two Nvidia DGX Spark** nodes (arm64 / GB10 / Ubuntu 24.04).

## Out of the box

1. Unbox the Spark. Cable mgmt LAN and, if you have two, the 200 Gb/s DAC.
2. Install a coding agent first (Grok Build, Codex, Claude Code, or similar).
3. Feed it [llms.txt](https://cmdlabtech.github.io/dgx-spark-ai-stack/llms.txt) and [llms-full.txt](https://cmdlabtech.github.io/dgx-spark-ai-stack/llms-full.txt) (human page: [llms.html](https://cmdlabtech.github.io/dgx-spark-ai-stack/llms.html)).
4. Answer the interview. The agent builds clustered TP=2 or isolated solo TP=1 from **current** `eugr/spark-vllm-docker` commands (`vllm-node`, no `--tf5`, `hf-download.sh`, no-Ray default).

The Pages root also has a tabbed generator that downloads the same procedure as `setup-node-a.sh` / `setup-node-b.sh`.

| | Architecture A — clustered | Architecture B — isolated solo |
|---|---|---|
| vLLM | One process, TP=2 over the DAC | One process per node, TP=1 |
| GPU | Shared pool | Each node owns its GB10 |
| Who sees prompts | Head API sees both UIs | Each API sees only its UI |
| Typical models | 122B-class FP8 (often cluster-only) | INT4 122B-class and/or 35B FP8 |
| When | Two nodes, one shared model | One Spark, isolation, or independent models |

Documentation names: **node-a** (personal + Hermes) and **node-b** (workload UI).
Documentation addresses only: `192.0.2.21` / `192.0.2.22` and `198.51.100.0/30` — never configure those on a real box.

Port 8000 must not be published on any overlay. There is no LiteLLM proxy. Templates live in `templates/`.
