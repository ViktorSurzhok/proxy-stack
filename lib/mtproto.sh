#!/usr/bin/env bash
# shellcheck shell=bash
# MTProto в Docker (telegrammessenger/proxy).

# Плагин compose v2 (если пакета docker-compose-plugin нет в apt — частый случай на минимальных образах).
_install_docker_compose_plugin_binary() {
  local arch raw
  raw="$(uname -m)"
  case "$raw" in
    x86_64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *) die "Неподдерживаемая архитектура для Docker Compose: $raw (нужен x86_64 или aarch64)" ;;
  esac
  local ver="${DOCKER_COMPOSE_PLUGIN_VERSION:-2.29.7}"
  local dest="/usr/local/lib/docker/cli-plugins"
  mkdir -p "$dest"
  info "Скачиваю docker-compose ${ver} → ${dest}/docker-compose …"
  curl -fsSL "https://github.com/docker/compose/releases/download/v${ver}/docker-compose-linux-${arch}" \
    -o "${dest}/docker-compose"
  chmod +x "${dest}/docker-compose"
}

mtproto_install_docker() {
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ca-certificates curl

  if ! dpkg -s docker.io &>/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker.io
  fi

  if docker compose version &>/dev/null 2>&1; then
    info "docker compose уже доступен"
  elif DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-compose-plugin 2>/dev/null; then
    info "Установлен пакет docker-compose-plugin из apt"
  else
    warn "Пакет docker-compose-plugin в apt не найден — ставлю плагин Compose v2 вручную (GitHub releases)."
    _install_docker_compose_plugin_binary
  fi

  docker compose version &>/dev/null || die "После установки команда «docker compose» недоступна. Проверьте docker.io и путь /usr/local/lib/docker/cli-plugins/"

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
