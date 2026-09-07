# NVIDIA DGX: At-Home AI Stack

Self-hosted inference and apps on **two Nvidia DGX Spark** nodes (arm64 / GB10 / Ubuntu 24.04).

Two layouts, one Pages site (`index.html` at the repository root). No extra paths.

| | Architecture A — clustered | Architecture B — isolated solo |
|---|---|---|
| vLLM | One process, TP=2 over Ray | One process per node, TP=1 |
| GPU | Shared pool | Each node owns its GB10 |
| Who sees prompts | Head API sees both UIs | Each API sees only its UI |
| Typical models | 122B-class FP8 (often cluster-only) | INT4 122B-class and/or dense ~27B FP8 |
| When | One shared model | Isolation, independent models |

The Pages page starts with **what** and **why**, then both architectures, then a **tabbed setup generator** (pick the model/layout, fill the table, download per-node scripts).

Documentation names: **node-a** (personal + Hermes) and **node-b** (workload UI).
Documentation addresses only: `192.0.2.21` / `192.0.2.22` and `198.51.100.0/30`.

Port 8000 must not be published on any overlay. Templates live in `templates/`.
