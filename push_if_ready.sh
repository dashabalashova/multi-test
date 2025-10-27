#!/usr/bin/env bash
set -euo pipefail

SSH_HOST="${SSH_HOST:-worker-2}"
REMOTE_USER="${REMOTE_USER:-}"   # optional, e.g. "root"
REMOTE="${REMOTE_USER:+$REMOTE_USER@}$SSH_HOST"

SUBMIT_DIR="${SLURM_SUBMIT_DIR:-$(pwd)}"
FLAG="$SUBMIT_DIR/image_ready.flag"

LOCAL_IMAGE="${LOCAL_IMAGE:-custom-pytorch-cu128:latest}"
GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/dashabalashova/custom-pytorch-cu128:latest}"

if [[ ! -f "$FLAG" ]]; then
  echo "Flag not found: $FLAG — nothing to do."
  exit 0
fi

echo "Flag found. Pushing $LOCAL_IMAGE -> $GHCR_IMAGE on $REMOTE"

ssh "$REMOTE" "docker image inspect '$LOCAL_IMAGE' >/dev/null || { echo 'Image $LOCAL_IMAGE not found on remote'; exit 2; } \
 && docker tag '$LOCAL_IMAGE' '$GHCR_IMAGE' \
 && docker push '$GHCR_IMAGE'"
