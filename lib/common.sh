#!/usr/bin/env bash
# shellcheck shell=bash
# proxy-stack: общие функции (логирование, ОС, сеть, секреты, порты).
# Подключается из install/uninstall/reconfigure после set -Eeuo pipefail.

: "${PS4:=+ }"

# Дефолты (переопределяются до source или в install.sh)
: "${STATE_DIR:=/opt/proxy-stack}"
: "${TINYPROXY_PORT:=8888}"
: "${MTPROTO_PORT:=443}"
: "${SECRETS_FILE:=$STATE_DIR/secrets.env}"
: "${SUMMARY_FILE:=$STATE_DIR/summary.txt}"
: "${INSTALL_LOG:=$STATE_DIR/install.log}"
: "${UFW_COMMENT_PREFIX:=proxy-stack}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${GREEN}[ok]${NC} $*"; }
info() { echo -e "${CYAN}[..]${NC} $*"; }
warn() { echo -e "${YELLOW}[!!]${NC} $*"; }
die() {
  echo -e "${RED}[xx]${NC} $*"
  exit 1
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Запустите от root: sudo ./install.sh"
}

load_os_release() {
  if [[ "$(uname -s)" == "Darwin" ]]; then
    die "Этот установщик только для Linux (Ubuntu/Debian на VPS). На macOS его запускать не нужно: \
установка выполняется на удалённом сервере по SSH. Пример: ssh root@ВАШ_VPS, затем git clone … && sudo ALLOWED_IPS=… ./install.sh"
  fi
  if [[ ! -r /etc/os-release ]]; then
    die "Не найден /etc/os-release — похоже, это не типичный Linux (Ubuntu/Debian). \
proxy-stack ставится на VPS с Ubuntu или Debian, не на macOS/Windows."
  fi
  # shellcheck source=/dev/null
  . /etc/os-release
}

assert_supported_os() {
  load_os_release
  case "${ID:-}" in
    ubuntu | debian) ;;
    *) die "Поддерживаются только Ubuntu и Debian (сейчас: ${ID:-unknown})" ;;
  esac
}

# Публичный IPv4 (для summary и ссылок MTProto)
detect_public_ipv4() {
  local ip=""
  ip="$(curl -4sS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$ip" || "$ip" == *" "* ]]; then
    ip="$(curl -4sS --max-time 8 https://ifconfig.me/ip 2>/dev/null || true)"
  fi
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  [[ -n "$ip" ]] || die "Не удалось определить публичный/основной IPv4"
  echo "$ip"
}

# Интерфейс маршрута по умолчанию (для логов; tinyproxy слушает 0.0.0.0)
detect_default_iface() {
  ip -4 route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

# IP клиента SSH, если доступен (часто ваш домашний IP на момент установки)
detect_ssh_client_ip() {
  local raw="${SSH_CONNECTION:-}"
  [[ -n "$raw" ]] || return 0
  echo "$raw" | awk '{print $1}'
}

# Проверка: слушает ли что-то TCP-порт на всех интерфейсах или localhost
tcp_port_in_use() {
  local port="$1"
  ss -H -ltn "sport = :$port" 2>/dev/null | grep -q . || return 1
}

# Возвращает 0 если порт свободен или занят только указанным процессом (по подстроке cmd)
port_free_or_owned_by() {
  local port="$1"
  local owner_substr="${2:-}"
  local line
  line="$(ss -H -ltnp "sport = :$port" 2>/dev/null | head -1 || true)"
  [[ -z "$line" ]] && return 0
  [[ -n "$owner_substr" && "$line" == *"$owner_substr"* ]] && return 0
  return 1
}

generate_mtproto_secret() {
  openssl rand -hex 16
}

generate_basic_auth_password() {
  openssl rand -base64 24 | tr -d '/+=' | head -c 24
}

ensure_state_dir() {
  mkdir -p "$STATE_DIR"
  mkdir -p "$STATE_DIR/docker/mtproto"
  chmod 700 "$STATE_DIR" 2>/dev/null || true
}

append_install_log_header() {
  ensure_state_dir
  umask 077
  : >>"$INSTALL_LOG"
  chmod 600 "$INSTALL_LOG" 2>/dev/null || true
  {
    echo "======== proxy-stack install log ========"
    echo "date: $(date -Iseconds 2>/dev/null || date)"
    echo "host: $(hostname -f 2>/dev/null || hostname)"
    echo "========================================="
  } >>"$INSTALL_LOG"
}

write_secrets_env() {
  ensure_state_dir
  umask 077
  {
    echo "# proxy-stack — автоматически сгенерировано. Права должны быть 600."
    echo "# Не коммитьте этот файл в git."
    printf 'STATE_DIR=%q\n' "$STATE_DIR"
    printf 'SERVER_PUBLIC_IP=%q\n' "$SERVER_PUBLIC_IP"
    printf 'DEFAULT_IFACE=%q\n' "${DEFAULT_IFACE:-}"
    printf 'TINYPROXY_PORT=%q\n' "$TINYPROXY_PORT"
    printf 'MTPROTO_PORT=%q\n' "$MTPROTO_PORT"
    printf 'MTPROTO_SECRET=%q\n' "$MTPROTO_SECRET"
    printf 'ALLOWED_IPS=%q\n' "$ALLOWED_IPS"
    printf 'ACCESS_MODE=%q\n' "$ACCESS_MODE"
    printf 'TINYPROXY_BASIC_AUTH_USER=%q\n' "${TINYPROXY_BASIC_AUTH_USER:-}"
    printf 'TINYPROXY_BASIC_AUTH_PASS=%q\n' "${TINYPROXY_BASIC_AUTH_PASS:-}"
    printf 'OPEN_PROXY_ACK=%q\n' "${OPEN_PROXY_ACK:-0}"
    printf 'INSTALLED_AT=%q\n' "$(date -Iseconds 2>/dev/null || date)"
  } >"$SECRETS_FILE.tmp"
  mv -f "$SECRETS_FILE.tmp" "$SECRETS_FILE"
  chmod 600 "$SECRETS_FILE"
}

read_secrets_env() {
  [[ -r "$SECRETS_FILE" ]] || die "Файл секретов не найден: $SECRETS_FILE (сначала install.sh)"
  # shellcheck disable=SC1090
  set +u
  source "$SECRETS_FILE"
  set -u
}

urlencode_query() {
  # минимальное кодирование для server/host в t.me (обычно IP — без спецсимволов)
  local s="$1"
  python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$s" 2>/dev/null || echo "$s"
}
