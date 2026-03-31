#!/usr/bin/env bash
# shellcheck shell=bash
# Проверки после установки: systemd, порты, docker, ufw.

verify_tinyproxy_running() {
  systemctl is-active --quiet tinyproxy
}

verify_tcp_port_listening() {
  local port="$1"
  ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .
}

verify_docker_mtproto_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx 'proxy-stack-mtproto'
}

verify_ufw_active() {
  ufw status 2>/dev/null | grep -qi "Status: active"
}
