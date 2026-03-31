#!/usr/bin/env bash
# =============================================================================
# proxy-stack — удаление правил UFW, остановка MTProto, откат конфига Tinyproxy
# Запуск: sudo ./uninstall.sh
# Опции окружения:
#   PURGE_STATE=1        — удалить $STATE_DIR (секреты и логи)
#   REMOVE_MTDATA=1      — docker compose down -v (том с данными MTProxy)
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/firewall.sh
source "$SCRIPT_DIR/lib/firewall.sh"
# shellcheck source=lib/tinyproxy.sh
source "$SCRIPT_DIR/lib/tinyproxy.sh"
# shellcheck source=lib/mtproto.sh
source "$SCRIPT_DIR/lib/mtproto.sh"

require_root
assert_supported_os
ufw_ensure_installed

info "Останавливаем MTProto (docker compose)…"
if [[ "${REMOVE_MTDATA:-0}" == "1" ]]; then
  mtproto_remove_volume
else
  mtproto_down
fi

info "Удаляем правила UFW с маркером proxy-stack svc=…"
ufw_delete_proxy_stack_rules

info "Восстанавливаем stock tinyproxy.conf (если есть резервная копия)…"
if [[ -f "$TINYPROXY_BACKUP" ]]; then
  tinyproxy_restore_backup
  systemctl restart tinyproxy || true
else
  warn "Резервная копия $TINYPROXY_BACKUP не найдена — tinyproxy.conf не трогаем."
fi

if [[ "${PURGE_STATE:-0}" == "1" ]]; then
  info "Удаляем каталог состояния $STATE_DIR…"
  rm -rf "$STATE_DIR"
fi

log "uninstall.sh завершён. При необходимости: apt purge tinyproxy; docker image rm telegrammessenger/proxy"
