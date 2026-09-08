## Agent-first bring-up

- New boxes: feed the agent `llms.txt` + `llms-full.txt`. Interview before any privileged command.
- Current launcher tag is `vllm-node`. Do not pass `--tf5`. Do not wait for `vllm-node-tf5`.
- Weights: `hf-download.sh`. Multi-node default is no-Ray.

## Hermes Agent installer (NousResearch)

- Installer: upstream `install.sh`
- Runtime: uv-managed Python 3.11 venv under `~/.hermes/hermes-agent/venv/`
- Gateway: systemd `hermes-gateway.service`
- Dashboard often `PartOf=` the gateway; restart the gateway after `config.yaml` edits
- Update: `hermes update` then confirm provider ids still match the local served name
- This stack does not use Ollama. Point Hermes at vLLM `:8000/v1` (Architecture B) or the documented inference URL (Architecture A)
- `model.max_tokens` must sit under the top-level `model:` key. Values under a fan-out / MoA block are ignored by the custom provider
- If the custom provider defaults `max_tokens` to the full context window, vLLM 400s and some builds enter a compression cooldown even with `compression.enabled: false`
- `skills.disabled` matches skill *names* (frontmatter `name` or the parent directory of `SKILL.md`), not category folder names. Nested skills stay indexed unless each name is listed

## vLLM restart footguns

- `launch-cluster.sh` can treat a leftover `vllm_node` name on the worker as “cluster already up” and skip creating the head. `systemctl` may still show `active`. Fix: `docker rm -f vllm_node` on both nodes, then `curl` `:8000/v1/models`, not status alone
- Open WebUI “OpenAI: Network Problem” is usually the URL. On the node that runs vLLM, `host.docker.internal:8000` works only after `--add-host=host.docker.internal:host-gateway`. On Architecture A, the workload node's container must use the head DAC address, not `host.docker.internal` (that name is the workload node itself)
- Solo and cluster both use the container name `vllm_node`. Remove it before switching layouts
- Disable the cluster unit on boot before leaving a node in solo mode

## Parser and context

- Qwen3.5 tool loops that emit coder-style calls need `--tool-call-parser qwen3_coder`, not `qwen3_xml`
- Cap `--max-model-len` on the first solo window. Recipe defaults near 262k plus `gpu-memory-utilization 0.7` can OOM a single GB10
