#!/usr/bin/env bash
# run_local_ci.sh — автоматизация: login -> worker build -> back -> sbatch -> push
set -euo pipefail
IFS=$'\n\t'

# --- Настройки (подправьте при необходимости) ---
REPO_URL="https://github.com/dashabalashova/multi-test.git"
WORKDIR="$HOME/multi-test"
DOCKER_DIR="docker2"
SSH_HOST="${SSH_HOST:-worker-2}"
REMOTE_USER="${REMOTE_USER:-root}"
REMOTE="${REMOTE_USER:+$REMOTE_USER@}$SSH_HOST"
LOCAL_IMAGE="${LOCAL_IMAGE:-custom-pytorch-cu128:latest}"
GHCR_IMAGE="${GHCR_IMAGE:-ghcr.io/dashabalashova/custom-pytorch-cu128:latest}"
# Сколько ждать (в секундах) появления image_ready.flag (по умолчанию 30 минут)
TIMEOUT_SECS="${TIMEOUT_SECS:-1800}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"

# --- helper ---
log(){ printf '\n[run_local_ci] %s\n' "$*"; }

# # 1) clone repo if needed
# if [[ ! -d "$WORKDIR" ]]; then
#   log "Repo not found at $WORKDIR — клонируем $REPO_URL"
#   git clone "$REPO_URL" "$WORKDIR"
# else
#   log "Repo exists at $WORKDIR — обновляем (git pull)"
#   (cd "$WORKDIR" && git pull --ff-only || true)
# fi

# 2) Build image on worker (ssh -> cd -> docker build -> optional enroot import)
log "SSH to $REMOTE: build docker image from $WORKDIR/$DOCKER_DIR"
ssh -o BatchMode=yes "$REMOTE" bash -lc "'
set -euo pipefail
cd \"$WORKDIR/$DOCKER_DIR\"
echo \"[remote] Building docker image: $LOCAL_IMAGE\"
docker build -t \"$LOCAL_IMAGE\" .
if command -v enroot >/dev/null 2>&1; then
  echo \"[remote] enroot found -> creating .sqsh\"
  enroot import --output \"${LOCAL_IMAGE//[:\/]/_}.sqsh\" \"dockerd://$LOCAL_IMAGE\" || echo \"[remote] enroot import failed (non-fatal)\"
else
  echo \"[remote] enroot not found — пропускаем enroot import\"
fi
'"

log "Remote build finished."

# 3) Back on login: submit sbatch
log "Submitting sbatch ($WORKDIR/code/sbatch4.sh)"
cd "$WORKDIR"
sbatch code/sbatch4.sh
log "sbatch submitted. Now polling for test result (image_ready.flag or test_result.txt) up to $TIMEOUT_SECS s"

# 4) Poll for result file (shared FS assumed)
end=$(( $(date +%s) + TIMEOUT_SECS ))
while true; do
  now=$(date +%s)
  if [[ $now -ge $end ]]; then
    log "TIMEOUT waiting for image_ready.flag (waited $TIMEOUT_SECS s). Exiting with failure."
    exit 2
  fi

  if [[ -f "$WORKDIR/image_ready.flag" ]]; then
    log "Found image_ready.flag — test passed on cluster."
    break
  fi

  if [[ -f "$WORKDIR/test_result.txt" ]]; then
    val=$(<"$WORKDIR/test_result.txt")
    log "Found test_result.txt -> $val"
    if [[ "$val" == "PASSED" ]]; then
      [[ -f "$WORKDIR/image_ready.flag" ]] || touch "$WORKDIR/image_ready.flag"
      break
    else
      log "Test result indicates failure: $val"
      exit 3
    fi
  fi

  sleep "$POLL_INTERVAL"
done

# 5) Show last logs (optional) — покажем последние 200 строк файла вывода SLURM, если есть
if ls "$WORKDIR/logs"/*-llama-finetune_*.txt >/dev/null 2>&1; then
  log "Тail последних 200 строк логов:"
  tail -n 200 "$WORKDIR/logs"/*-llama-finetune_*.txt || true
else
  log "Лог-файлы не найдены в $WORKDIR/logs (пропускаем показ)."
fi

# 6) Login to ghcr and push (push_if_ready.sh выполнит push на remote)
if [[ -z "${GHCR_PAT:-}" ]]; then
  log "Переменная GHCR_PAT не задана — задайте GHCR_PAT экспортом перед запуском, например:"
  log '  export GHCR_PAT="ghp_..."'
  log "Попытка продолжить без логина — push может провалиться."
else
  log "Logging in to ghcr.io"
  echo "$GHCR_PAT" | docker login ghcr.io -u "${GITHUB_USER:-$USER}" --password-stdin
fi

# 7) Call push_if_ready.sh (он выполнит ssh на worker и пуш образа оттуда)
# Передаём нужные переменные в окружение
log "Calling push_if_ready.sh to tag & push image from remote ($SSH_HOST)"
SSH_HOST="$SSH_HOST" REMOTE_USER="$REMOTE_USER" LOCAL_IMAGE="$LOCAL_IMAGE" GHCR_IMAGE="$GHCR_IMAGE" ./push_if_ready.sh

log "Done."
