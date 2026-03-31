#!/usr/bin/env bash
# =============================================================================
# proxy-stack — повторное применение конфигурации (IP, порты, firewall, compose)
#
# Примеры:
#   sudo ./reconfigure.sh
#   ALLOWED_IPS_OVERRIDE=203.0.113.10,198.51.100.2 sudo ./reconfigure.sh
#   TINYPROXY_PORT=8899 MTPROTO_PORT=8443 sudo ./reconfigure.sh
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
# shellcheck source=lib/verify.sh
source "$SCRIPT_DIR/lib/verify.sh"

require_root
assert_supported_os
read_secrets_env

SERVER_PUBLIC_IP="$(detect_public_ipv4)"
DEFAULT_IFACE="$(detect_default_iface || true)"

declare -a ALLOW_IP_LIST=()
_split_csv_to_array() {
  local csv="$1"
  ALLOW_IP_LIST=()
  local IFS=','
  local part
  for part in $csv; do
    part="${part// /}"
    [[ -n "$part" ]] && ALLOW_IP_LIST+=("$part")
  done
}

if [[ -n "${ALLOWED_IPS_OVERRIDE:-}" ]]; then
  _split_csv_to_array "$ALLOWED_IPS_OVERRIDE"
else
  _split_csv_to_array "${ALLOWED_IPS:-}"
fi

ACCESS_MODE="${ACCESS_MODE:-allowed_ips}"

if [[ "$ACCESS_MODE" == "allowed_ips" || "$ACCESS_MODE" == "basic_auth" ]]; then
  [[ ${#ALLOW_IP_LIST[@]} -gt 0 ]] || die "Нет IP в secrets (ALLOWED_IPS). Задайте ALLOWED_IPS_OVERRIDE=ip1,ip2"
fi

info "Перезапись tinyproxy (${ACCESS_MODE}), порт ${TINYPROXY_PORT}…"
export TINYPROXY_BASIC_AUTH_USER TINYPROXY_BASIC_AUTH_PASS
tinyproxy_write_config "$TINYPROXY_PORT" "$ACCESS_MODE" "${ALLOW_IP_LIST[@]}"
tinyproxy_enable_and_restart

info "Обновление MTProto compose, порт ${MTPROTO_PORT}…"
mtproto_write_compose
mtproto_up

info "Обновление UFW…"
ufw_ensure_installed
ufw_delete_proxy_stack_rules
ufw_allow_mtproto_port "$MTPROTO_PORT"
if [[ "$ACCESS_MODE" == "open_warning" ]]; then
  ufw_allow_tinyproxy_world "$TINYPROXY_PORT"
else
  ufw_allow_tinyproxy_from_ips "$TINYPROXY_PORT" "${ALLOW_IP_LIST[@]}"
fi

ALLOWED_IPS_CSV="$(IFS=','; echo "${ALLOW_IP_LIST[*]}")"
# Для open_warning список может быть пустым — сохраняем прежний CSV из secrets, если пусто
if [[ -z "$ALLOWED_IPS_CSV" ]]; then
  ALLOWED_IPS_CSV="${ALLOWED_IPS:-}"
fi
export ALLOWED_IPS="$ALLOWED_IPS_CSV"
export SERVER_PUBLIC_IP DEFAULT_IFACE MTPROTO_SECRET MTPROTO_PORT TINYPROXY_PORT ACCESS_MODE OPEN_PROXY_ACK
write_secrets_env

TP_OK="not running"
MP_OK="not running"
FW_OK="not active"
verify_tinyproxy_running && TP_OK="running" || true
verify_docker_mtproto_running && MP_OK="running" || true
verify_ufw_active && FW_OK="active" || true

ENC_HOST="$(urlencode_query "$SERVER_PUBLIC_IP")"
TG_PROXY_URL="tg://proxy?server=${ENC_HOST}&port=${MTPROTO_PORT}&secret=${MTPROTO_SECRET}"
HTTPS_PROXY_URL="https://t.me/proxy?server=${ENC_HOST}&port=${MTPROTO_PORT}&secret=${MTPROTO_SECRET}"
BROWSER_HINT="HTTP-прокси: ${SERVER_PUBLIC_IP}:${TINYPROXY_PORT}"
[[ "$ACCESS_MODE" == "basic_auth" ]] && BROWSER_HINT="${BROWSER_HINT} (логин/пароль — в ${SECRETS_FILE})"

umask 077
cat >"$SUMMARY_FILE" <<EOF
═══════════════════════════════════════════════════════════════════
 proxy-stack — сводка (reconfigure)
 Обновлено: $(date -Iseconds 2>/dev/null || date)
═══════════════════════════════════════════════════════════════════

[ Tinyproxy ]
  Host:           ${SERVER_PUBLIC_IP}
  Port:           ${TINYPROXY_PORT}
  Access mode:    ${ACCESS_MODE}
  Allowed IPs:    ${ALLOWED_IPS_CSV:-n/a}
  Browser setup:  ${BROWSER_HINT}

[ MTProto ]
  Server:         ${SERVER_PUBLIC_IP}
  Port:           ${MTPROTO_PORT}
  Secret:         ${MTPROTO_SECRET}
  tg://proxy:     ${TG_PROXY_URL}
  https://t.me:   ${HTTPS_PROXY_URL}

[ Files ]
  Secrets file:    ${SECRETS_FILE}
  Install log:     ${INSTALL_LOG}
  Summary:         ${SUMMARY_FILE}

[ Status ]
  Tinyproxy:      ${TP_OK}
  MTProto:        ${MP_OK}
  Firewall:       ${FW_OK}

═══════════════════════════════════════════════════════════════════
EOF
chmod 600 "$SUMMARY_FILE"

cat "$SUMMARY_FILE"
log "reconfigure завершён."
