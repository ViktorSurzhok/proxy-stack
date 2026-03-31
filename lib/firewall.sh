#!/usr/bin/env bash
# shellcheck shell=bash
# UFW: не трогаем чужие правила; управляем только помеченными proxy-stack svc=...

: "${UFW_COMMENT_PREFIX:=proxy-stack}"

ufw_ensure_installed() {
  if ! command -v ufw >/dev/null 2>&1; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ufw
  fi
}

# Удаляет только правила с подстрокой "proxy-stack svc=" в комментарии (см. ufw status numbered).
# Важно: при set -o pipefail grep без совпадений даёт код 1 — нельзя вставлять такой pipeline в $(...) без проверки.
ufw_delete_proxy_stack_rules() {
  local out num
  while true; do
    out="$(ufw status numbered 2>/dev/null || true)"
    if ! echo "$out" | grep -q 'proxy-stack svc='; then
      break
    fi
    num="$(echo "$out" | grep 'proxy-stack svc=' | sed -n 's/^\[[[:space:]]*\([0-9]\+\)\].*/\1/p' | sort -rn | head -1)"
    [[ -z "$num" ]] && break
    echo "y" | ufw delete "$num" >/dev/null 2>&1 || break
  done
}

# Первый запуск UFW: безопасные политики и SSH до enable (чтобы не потерять доступ).
ufw_bootstrap_if_inactive() {
  local st
  st="$(ufw status 2>/dev/null || true)"
  if echo "$st" | grep -qi "Status: active"; then
    return 0
  fi
  ufw default deny incoming
  ufw default allow outgoing
  # SSH — обязателен до ufw enable
  ufw limit 22/tcp comment "ssh"
  ufw --force enable
}

ufw_allow_mtproto_port() {
  local port="$1"
  ufw allow "$port/tcp" comment "${UFW_COMMENT_PREFIX} svc=mtproto port=${port}"
}

ufw_allow_tinyproxy_from_ips() {
  local port="$1"
  shift
  local ip
  for ip in "$@"; do
    [[ -n "$ip" ]] || continue
    ufw allow from "$ip" to any port "$port" proto tcp comment "${UFW_COMMENT_PREFIX} svc=tinyproxy from=${ip}"
  done
}

ufw_allow_tinyproxy_world() {
  local port="$1"
  ufw allow "$port/tcp" comment "${UFW_COMMENT_PREFIX} svc=tinyproxy world-open"
}

ufw_status_verbose() {
  ufw status verbose || true
}
