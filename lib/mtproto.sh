#!/usr/bin/env bash
# shellcheck shell=bash
# MTProto в Docker (telegrammessenger/proxy).

mtproto_install_docker() {
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io docker-compose-plugin ca-certificates curl
  systemctl enable docker >/dev/null 2>&1 || true
  systemctl start docker
}

mtproto_write_compose() {
  local dir="$STATE_DIR/docker/mtproto"
  mkdir -p "$dir"
  umask 077
  cat >"$dir/docker-compose.yml" <<'YAML'
services:
  mtproto-proxy:
    image: telegrammessenger/proxy:latest
    container_name: proxy-stack-mtproto
    restart: unless-stopped
    environment:
      SECRET: ${MTPROTO_SECRET}
      WORKERS: ${MTPROTO_WORKERS:-2}
    ports:
      - "${MTPROTO_PUBLISH_PORT}:443"
    volumes:
      - mtproto-data:/data
volumes:
  mtproto-data:
YAML
  cat >"$dir/.env" <<EOF
MTPROTO_SECRET=${MTPROTO_SECRET}
MTPROTO_PUBLISH_PORT=${MTPROTO_PORT}
MTPROTO_WORKERS=${MTPROTO_WORKERS:-2}
EOF
  chmod 600 "$dir/.env"
}

mtproto_up() {
  local dir="$STATE_DIR/docker/mtproto"
  (cd "$dir" && docker compose pull --quiet 2>/dev/null || true)
  (cd "$dir" && docker compose up -d)
}

mtproto_down() {
  local dir="$STATE_DIR/docker/mtproto"
  [[ -f "$dir/docker-compose.yml" ]] || return 0
  (cd "$dir" && docker compose down) || true
}

mtproto_remove_volume() {
  local dir="$STATE_DIR/docker/mtproto"
  [[ -f "$dir/docker-compose.yml" ]] || return 0
  (cd "$dir" && docker compose down -v) || true
}
