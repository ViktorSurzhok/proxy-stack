#!/usr/bin/env bash
# =============================================================================
# proxy-stack — git pull + повторный install.sh (идемпотентно)
# Запуск: sudo ./update.sh
# =============================================================================
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

[[ "$(id -u)" -eq 0 ]] || { echo "Запустите: sudo ./update.sh" >&2; exit 1; }

if [[ -d .git ]]; then
  git pull --ff-only
else
  echo "[!!] Нет .git — пропускаем git pull." >&2
fi

exec env "PATH=$PATH" "$ROOT/install.sh"
