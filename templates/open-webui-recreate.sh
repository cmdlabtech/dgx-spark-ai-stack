#!/usr/bin/env bash
# Recreate Open WebUI with host.docker.internal -> host gateway.
# Does not delete the named volume. Substitute image tag if you pin one.
# For Architecture A on node-b, set OPENAI_API_BASE_URL to http://<node-a-dac>:8000/v1
set -euo pipefail

NAME="${OPENWEBUI_NAME:-open-webui}"
VOLUME="${OPENWEBUI_VOLUME:-open-webui}"
IMAGE="${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
BASE="${OPENAI_API_BASE_URL:-http://host.docker.internal:8000/v1}"

docker stop "$NAME" >/dev/null 2>&1 || true
docker rm "$NAME" >/dev/null 2>&1 || true

docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  -p 8080:8080 \
  --add-host=host.docker.internal:host-gateway \
  -e OPENAI_API_BASE_URL="$BASE" \
  -e OPENAI_API_KEY="not-needed" \
  -e ENABLE_OLLAMA_API=False \
  -e WEBUI_AUTH=True \
  -e ENABLE_KB_EXEC=true \
  -v "${VOLUME}:/app/backend/data" \
  "$IMAGE"

echo "Connections URL inside the container: $BASE"
echo "Fallback if the hostname fails: http://172.17.0.1:8000/v1"
