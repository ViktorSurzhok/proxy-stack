#!/usr/bin/env bash
# shellcheck shell=bash
# Установка и конфигурация tinyproxy (нативно, systemd).

TINYPROXY_CONF="/etc/tinyproxy/tinyproxy.conf"
TINYPROXY_BACKUP="/etc/tinyproxy/tinyproxy.conf.bak.before-proxy-stack"

tinyproxy_install_package() {
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tinyproxy
}

tinyproxy_backup_stock_config() {
  [[ -f "$TINYPROXY_CONF" ]] || return 0
  [[ -f "$TINYPROXY_BACKUP" ]] && return 0
  cp -a "$TINYPROXY_CONF" "$TINYPROXY_BACKUP"
  chmod 600 "$TINYPROXY_BACKUP" 2>/dev/null || true
}

# Генерирует полный tinyproxy.conf
tinyproxy_write_config() {
  local port="$1"
  local access_mode="$2" # allowed_ips | basic_auth | open_warning
  shift 2
  local -a allow_ips=("$@")

  tinyproxy_backup_stock_config

  umask 027
  cat >"$TINYPROXY_CONF" <<EOF
## proxy-stack — автоматически сгенерировано. Резервная копия: ${TINYPROXY_BACKUP}
User tinyproxy
Group tinyproxy
Port ${port}
Listen 0.0.0.0
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
LogLevel Info
PidFile "/run/tinyproxy/tinyproxy.pid"
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0
ViaProxyName "tinyproxy"
DisableViaHeader Yes
EOF

  case "$access_mode" in
    allowed_ips)
      if [[ ${#allow_ips[@]} -eq 0 ]]; then
        die "ACCESS_MODE=allowed_ips, но список IP пуст"
      fi
      local ip
      for ip in "${allow_ips[@]}"; do
        [[ -n "$ip" ]] || continue
        echo "Allow ${ip}" >>"$TINYPROXY_CONF"
      done
      ;;
    basic_auth)
      # Дополнительно к сетевому ограничению (если заданы ALLOWED_IPS — они тоже в конфиг)
      for ip in "${allow_ips[@]}"; do
        [[ -n "$ip" ]] || continue
        echo "Allow ${ip}" >>"$TINYPROXY_CONF"
      done
      [[ -n "${TINYPROXY_BASIC_AUTH_USER:-}" && -n "${TINYPROXY_BASIC_AUTH_PASS:-}" ]] || die "basic_auth без логина/пароля"
      echo "BasicAuth ${TINYPROXY_BASIC_AUTH_USER} ${TINYPROXY_BASIC_AUTH_PASS}" >>"$TINYPROXY_CONF"
      ;;
    open_warning)
      echo "Allow 0.0.0.0/0" >>"$TINYPROXY_CONF"
      ;;
    *)
      die "Неизвестный ACCESS_MODE: $access_mode"
      ;;
  esac

  chmod 640 "$TINYPROXY_CONF"
  chown root:tinyproxy "$TINYPROXY_CONF" 2>/dev/null || true
}

tinyproxy_enable_and_restart() {
  systemctl enable tinyproxy >/dev/null 2>&1 || true
  systemctl restart tinyproxy
}

tinyproxy_restore_backup() {
  [[ -f "$TINYPROXY_BACKUP" ]] || return 0
  cp -a "$TINYPROXY_BACKUP" "$TINYPROXY_CONF"
}
