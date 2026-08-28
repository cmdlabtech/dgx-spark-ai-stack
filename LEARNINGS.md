## Hermes Agent installer (NousResearch, 2026-05)
- Installer script: https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh
- Python runtime: uv manages Python 3.11 venv at ~/.hermes/hermes-agent/venv/
- Node.js: 22 LTS, downloaded to ~/.hermes/node/, symlinked to ~/.local/bin/
- Submodules: mini-swe-agent (terminal tools), tinker-atropos (RL skill training)
- System deps installed via apt: ripgrep, ffmpeg
- Config layout: ~/.hermes/config.yaml, ~/.hermes/.env, ~/.hermes/SOUL.md (all top-level)
- Skills: bundled skills seeded to ~/.hermes/skills/ via skills_sync.py on install
- hermes CLI: ~/.hermes/hermes-agent/venv/bin/hermes → symlinked to ~/.local/bin/hermes
- Gateway: systemd service (hermes-gateway.service) — `hermes gateway install --system`
- Update: `hermes update` pulls latest, restarts gateway
- SOUL.md: hot-reloaded per message, no restart needed
- This stack does NOT use Ollama — Hermes points at LiteLLM :8001 as custom OpenAI endpoint
- NVIDIA DGX playbook for Hermes assumes Ollama :11434 — ignore for this stack
- `hermes mcp test <server-name>` is canonical for verifying MCP server connectivity

## vLLM cluster restart footguns (2026-08)
- `launch-cluster.sh` has a stale-state bug: if a `vllm_node` container name is still registered on the worker (spark-02) from a prior run, it concludes the whole cluster is "already running" and skips launching the head container on spark-01 — then fails silently trying to `docker exec` into a head container that was never created. `systemctl status` still reports `active (exited)` with no error. Fix: `docker rm -f vllm_node` on both nodes before restarting the service, then verify with `docker ps -a` + `curl localhost:8000/v1/models`, not just systemctl status.
- Open WebUI "OpenAI: Network Problem" toast is almost always a wrong URL, not a broken connection: spark-01 uses `http://host.docker.internal:8000/v1` (resolves to itself); spark-02 must use the head node's DAC IP directly (`http://<spark-01-dac-ip>:8000/v1`) — `host.docker.internal` on spark-02 resolves to spark-02, where nothing listens on 8000. Isolate with `curl` on the host first, then `docker exec open-webui curl ...` from inside the container, before touching UI config.
