#!/usr/bin/env bash
# =============================================================================
# proxy-stack — установка Tinyproxy (HTTP) + MTProto (Telegram) + UFW
# Запуск: git clone … && cd … && sudo ./install.sh
# Требования: Ubuntu/Debian, root, чистые или заранее проверенные порты.
# Bash: set -Eeuo pipefail, комментарии для сопровождения.
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

# --- Переменные окружения (опционально) --------------------------------------
# TINYPROXY_PORT=8888
# MTPROTO_PORT=443
# ALLOWED_IPS="1.2.3.4,5.6.7.8"   # IP, с которых разрешён HTTP-прокси (рекомендуется)
# TINYPROXY_BASIC_AUTH_USER / TINYPROXY_BASIC_AUTH_PASS — опционально (см. README)
# CONFIRM_OPEN_PROXY=I_UNDERSTAND_OPEN_PROXY_RISK — «открытый» Tinyproxy (не рекомендуется)
# STATE_DIR=/opt/proxy-stack

trap 'echo -e "${RED}[xx]${NC} Прервано или ошибка (строка ${LINENO}, статус $?). См. ${INSTALL_LOG:-лог}." >&2' ERR

usage() {
  cat <<EOF
Использование: sudo ./install.sh

Перед запуском задайте при необходимости ALLOWED_IPS (через запятую) — IP для доступа к Tinyproxy.
Если вы вошли по SSH, по умолчанию подставится IP клиента SSH.
EOF
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { usage; exit 0; }

require_root
assert_supported_os

ensure_state_dir
append_install_log_header
exec > >(tee -a "$INSTALL_LOG") 2>&1

info "proxy-stack install, STATE_DIR=$STATE_DIR"

DEFAULT_IFACE="$(detect_default_iface || true)"
SERVER_PUBLIC_IP="$(detect_public_ipv4)"
SSH_CLIENT_IP="$(detect_ssh_client_ip || true)"

info "Публичный IPv4 сервера: $SERVER_PUBLIC_IP (интерфейс по умолчанию: ${DEFAULT_IFACE:-unknown})"

# --- Разбор ALLOWED_IPS ------------------------------------------------------
declare -a ALLOW_IP_LIST=()
if [[ -n "${ALLOWED_IPS:-}" ]]; then
  IFS=',' read -ra _parts <<<"${ALLOWED_IPS// /}"
  for x in "${_parts[@]}"; do
    [[ -n "$x" ]] && ALLOW_IP_LIST+=("$x")
  done
fi
if [[ ${#ALLOW_IP_LIST[@]} -eq 0 && -n "${SSH_CLIENT_IP:-}" ]]; then
  ALLOW_IP_LIST+=("$SSH_CLIENT_IP")
  info "ALLOWED_IPS не задан — используем IP SSH-клиента: $SSH_CLIENT_IP"
fi

ACCESS_MODE="allowed_ips"
if [[ "${CONFIRM_OPEN_PROXY:-}" == "I_UNDERSTAND_OPEN_PROXY_RISK" ]]; then
  ACCESS_MODE="open_warning"
  warn "Включён режим открытого Tinyproxy (Allow 0.0.0.0/0 + UFW world). Это риск open proxy."
elif [[ -n "${TINYPROXY_BASIC_AUTH_USER:-}" || -n "${TINYPROXY_BASIC_AUTH_PASS:-}" ]]; then
  if [[ -z "${TINYPROXY_BASIC_AUTH_USER:-}" || -z "${TINYPROXY_BASIC_AUTH_PASS:-}" ]]; then
    die "Задайте оба: TINYPROXY_BASIC_AUTH_USER и TINYPROXY_BASIC_AUTH_PASS"
  fi
  ACCESS_MODE="basic_auth"
  [[ ${#ALLOW_IP_LIST[@]} -gt 0 ]] || die "С BasicAuth всё равно задайте ALLOWED_IPS (или SSH) — не открываем 0.0.0.0/0 без явного OPEN."
elif [[ ${#ALLOW_IP_LIST[@]} -eq 0 ]]; then
  die "Не удалось определить IP для Tinyproxy. Запустите: ALLOWED_IPS=ваш.публичный.ip sudo ./install.sh"
fi

# --- Порты: конфликты --------------------------------------------------------
if tcp_port_in_use "$TINYPROXY_PORT"; then
  port_free_or_owned_by "$TINYPROXY_PORT" "tinyproxy" || die "Порт $TINYPROXY_PORT уже занят (Tinyproxy). Задайте TINYPROXY_PORT=другой"
fi

if tcp_port_in_use "$MTPROTO_PORT"; then
  if docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -q "proxy-stack-mtproto.*:${MTPROTO_PORT}->443"; then
    info "Порт $MTPROTO_PORT похоже уже занят контейнером MTProto — продолжаем."
  else
    warn "Порт $MTPROTO_PORT занят (часто nginx/caddy). Переключаем MTProto на 8443."
    MTPROTO_PORT=8443
    if tcp_port_in_use "$MTPROTO_PORT"; then
      die "И 8443 занят. Освободите порт или задайте MTPROTO_PORT вручную."
    fi
  fi
fi

# --- Секреты: при повторном запуске сохраняем MTProto secret ------------------
MTPROTO_SECRET=""
if [[ -r "$SECRETS_FILE" ]]; then
  MTPROTO_SECRET="$(
    set +u
    # shellcheck disable=SC1090
    source "$SECRETS_FILE"
    printf '%s' "${MTPROTO_SECRET:-}"
  )"
  [[ -n "$MTPROTO_SECRET" ]] && info "Повторная установка: сохраняем существующий MTProto SECRET из secrets.env."
fi
if [[ -z "$MTPROTO_SECRET" ]]; then
  MTPROTO_SECRET="$(generate_mtproto_secret)"
fi

if [[ "$ACCESS_MODE" == "basic_auth" && -z "${TINYPROXY_BASIC_AUTH_PASS:-}" ]]; then
  TINYPROXY_BASIC_AUTH_PASS="$(generate_basic_auth_password)"
fi

if [[ "$ACCESS_MODE" == "open_warning" ]]; then
  OPEN_PROXY_ACK=1
else
  OPEN_PROXY_ACK=0
fi

# --- Пакеты ------------------------------------------------------------------
info "Установка пакетов (tinyproxy, ufw, docker, curl, openssl)…"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  ca-certificates curl openssl ufw tinyproxy iptables

tinyproxy_install_package
mtproto_install_docker

# --- Конфигурация сервисов ---------------------------------------------------
info "Запись конфигурации Tinyproxy (режим: $ACCESS_MODE)…"
tinyproxy_write_config "$TINYPROXY_PORT" "$ACCESS_MODE" "${ALLOW_IP_LIST[@]}"
tinyproxy_enable_and_restart

info "Запись docker-compose для MTProto (telegrammessenger/proxy)…"
mtproto_write_compose
mtproto_up

# --- Firewall ----------------------------------------------------------------
info "Настройка UFW (только правила с маркером proxy-stack svc=)…"
ufw_ensure_installed
ufw_bootstrap_if_inactive
ufw_delete_proxy_stack_rules
ufw_allow_mtproto_port "$MTPROTO_PORT"
if [[ "$ACCESS_MODE" == "open_warning" ]]; then
  ufw_allow_tinyproxy_world "$TINYPROXY_PORT"
else
  ufw_allow_tinyproxy_from_ips "$TINYPROXY_PORT" "${ALLOW_IP_LIST[@]}"
fi
ufw_status_verbose >/dev/null

# --- Сохранение секретов и сводки -------------------------------------------
ALLOWED_IPS_CSV="$(IFS=','; echo "${ALLOW_IP_LIST[*]}")"
export ALLOWED_IPS="$ALLOWED_IPS_CSV"
export ACCESS_MODE SERVER_PUBLIC_IP DEFAULT_IFACE MTPROTO_SECRET MTPROTO_PORT TINYPROXY_PORT OPEN_PROXY_ACK
write_secrets_env

# --- Проверки ----------------------------------------------------------------
TP_OK="not running"
MP_OK="not running"
FW_OK="not active"
verify_tinyproxy_running && TP_OK="running" || warn "Tinyproxy не в состоянии active после restart."
verify_tcp_port_listening "$TINYPROXY_PORT" && true || warn "Порт $TINYPROXY_PORT не слушается."
verify_docker_mtproto_running && MP_OK="running" || warn "Контейнер MTProto не найден в docker ps."
verify_ufw_active && FW_OK="active" || warn "UFW не active."

# Ссылки MTProto (порт в ссылке обязан совпадать с опубликованным)
ENC_HOST="$(urlencode_query "$SERVER_PUBLIC_IP")"
TG_PROXY_URL="tg://proxy?server=${ENC_HOST}&port=${MTPROTO_PORT}&secret=${MTPROTO_SECRET}"
HTTPS_PROXY_URL="https://t.me/proxy?server=${ENC_HOST}&port=${MTPROTO_PORT}&secret=${MTPROTO_SECRET}"

BROWSER_HINT="HTTP-прокси: ${SERVER_PUBLIC_IP}:${TINYPROXY_PORT} (тип HTTP, не SOCKS)."
if [[ "$ACCESS_MODE" == "basic_auth" ]]; then
  BROWSER_HINT="${BROWSER_HINT} Логин/пароль: ${TINYPROXY_BASIC_AUTH_USER} / ${TINYPROXY_BASIC_AUTH_PASS} (если браузер спрашивает)."
fi

umask 077
cat >"$SUMMARY_FILE" <<EOF
═══════════════════════════════════════════════════════════════════
 proxy-stack — сводка подключения
 Сгенерировано: $(date -Iseconds 2>/dev/null || date)
═══════════════════════════════════════════════════════════════════

[ Tinyproxy ]
  Host:           ${SERVER_PUBLIC_IP}
  Port:           ${TINYPROXY_PORT}
  Access mode:    ${ACCESS_MODE}
  Allowed IPs:    ${ALLOWED_IPS_CSV}
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

# --- Вывод для оператора -----------------------------------------------------
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD} proxy-stack — установка завершена${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════${NC}"
cat "$SUMMARY_FILE"
echo ""
log "Готово. Полная сводка: $SUMMARY_FILE"
