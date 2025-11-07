#!/bin/bash
set -euo pipefail
LOG_TAG="nginx-git-sync"
REPO_DIR="/etc/nginx"
export GIT_SSH_COMMAND="ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=accept-new"
if ! command -v git >/dev/null 2>&1; then
  logger -t "$LOG_TAG" "git non trovato"
  exit 1
fi
if [ ! -d "$REPO_DIR/.git" ]; then
  logger -t "$LOG_TAG" "repository non inizializzato in $REPO_DIR"
  exit 1
fi
cd "$REPO_DIR"
if ! git diff --quiet || ! git diff --cached --quiet; then
  logger -t "$LOG_TAG" "ci sono modifiche locali non committate: sincronizzazione saltata"
  exit 0
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  logger -t "$LOG_TAG" "remoto origin non configurato"
  exit 1
fi
logger -t "$LOG_TAG" "fetch da origin"
if ! git fetch origin; then
  logger -t "$LOG_TAG" "fetch fallito"
  exit 1
fi
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse origin/main)
if [ "$LOCAL_SHA" = "$REMOTE_SHA" ]; then
  logger -t "$LOG_TAG" "nessun aggiornamento disponibile"
  exit 0
fi
logger -t "$LOG_TAG" "pull origin/main"
if ! git pull --ff-only origin main; then
  logger -t "$LOG_TAG" "pull fallito"
  exit 1
fi
logger -t "$LOG_TAG" "test configurazione nginx"
if ! nginx -t; then
  logger -t "$LOG_TAG" "nginx -t fallito, rollback"
  git reset --hard "$LOCAL_SHA"
  exit 1
fi
logger -t "$LOG_TAG" "ricarico nginx"
if systemctl reload nginx; then
  logger -t "$LOG_TAG" "aggiornamento completato"
else
  logger -t "$LOG_TAG" "reload fallito, rollback"
  git reset --hard "$LOCAL_SHA"
  systemctl reload nginx || true
  exit 1
fi
