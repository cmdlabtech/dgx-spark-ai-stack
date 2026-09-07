#!/usr/bin/env bash
# Recreate Open WebUI with host.docker.internal -> host gateway.
# Does not delete the named volume. Substitute image tag if you pin one.
set -euo pipefail

NAME="${OPENWEBUI_NAME:-open-webui}"
VOLUME="${OPENWEBUI_VOLUME:-open-webui}"
IMAGE="${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"

docker stop "$NAME" >/dev/null 2>&1 || true
docker rm "$NAME" >/dev/null 2>&1 || true

docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  -p 8080:8080 \
  --add-host=host.docker.internal:host-gateway \
  -e ENABLE_KB_EXEC=true \
  -v "${VOLUME}:/app/backend/data" \
  "$IMAGE"

echo "Connections URL inside the container: http://host.docker.internal:8000/v1"
echo "Fallback if the name fails: http://172.17.0.1:8000/v1"
