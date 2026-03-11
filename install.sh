#!/bin/bash
# ============================================================
#  proxy-stack install.sh
#  Поднимает: SOCKS5 (Dante) + HTTP (Tinyproxy) + Outline VPN
#  Запуск: sudo bash install.sh
#  Или одной командой:
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/ViktorSurzhok/proxy-stack/main/install.sh)"
# ============================================================

set -e

# ─── Цвета ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[✗] ОШИБКА: $1${NC}"; exit 1; }

# ─── Параметры (можно переопределить переменными окружения) ───
SOCKS_PORT="${SOCKS_PORT:-1080}"
HTTP_PORT="${HTTP_PORT:-8888}"
SOCKS_USER="${SOCKS_USER:-proxyuser}"
SOCKS_PASS="${SOCKS_PASS:-$(tr -dc 'A-Za-z0-9!@#$' </dev/urandom | head -c 16)}"
INSTALL_DIR="${INSTALL_DIR:-/opt/proxy-stack}"
OUTLINE_DIR="${OUTLINE_DIR:-/opt/outline}"

# ─── Проверки ────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Запусти скрипт от root: sudo bash install.sh"

OS=$(lsb_release -si 2>/dev/null || cat /etc/os-release | grep ^ID= | cut -d= -f2)
[[ "$OS" != "Ubuntu" && "$OS" != "Debian" && "$OS" != "ubuntu" && "$OS" != "debian" ]] && \
    warn "Протестировано на Ubuntu/Debian. Продолжаем на свой страх и риск..."

# ─── Определяем сетевой интерфейс и IP ───────────────────────
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
SERVER_IP=$(curl -s --max-time 5 https://ifconfig.me || curl -s --max-time 5 https://api.ipify.org)
[[ -z "$SERVER_IP" ]] && SERVER_IP=$(hostname -I | awk '{print $1}')

info "Интерфейс: $IFACE | IP: $SERVER_IP"

# ─── Создаём рабочую директорию ──────────────────────────────
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo ""
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo -e "${BOLD}   proxy-stack installer                  ${NC}"
echo -e "${BOLD}══════════════════════════════════════════${NC}"
echo ""

# ════════════════════════════════════════════
# 1. СИСТЕМНЫЕ ЗАВИСИМОСТИ
# ════════════════════════════════════════════
info "Обновляем пакеты..."
apt-get update -qq

info "Устанавливаем зависимости..."
apt-get install -y -qq curl wget git ufw ca-certificates gnupg lsb-release

# ════════════════════════════════════════════
# 2. DOCKER
# ════════════════════════════════════════════
if ! command -v docker &>/dev/null; then
    info "Устанавливаем Docker..."
    curl -fsSL https://get.docker.com | bash -s -- -y
    systemctl enable docker
    systemctl start docker
    log "Docker установлен"
else
    log "Docker уже установлен ($(docker --version | cut -d' ' -f3 | tr -d ','))"
fi

if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null 2>&1; then
    info "Устанавливаем docker-compose..."
    apt-get install -y -qq docker-compose-plugin || \
        curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
             -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose
fi

# ════════════════════════════════════════════
# 3. КОНФИГИ
# ════════════════════════════════════════════
info "Генерируем конфиги..."

# ── Dante SOCKS5 ──────────────────────────
mkdir -p "$INSTALL_DIR/dante"

cat > "$INSTALL_DIR/dante/danted.conf" <<EOF
logoutput: stderr
internal: 0.0.0.0 port = $SOCKS_PORT
external: $IFACE

socksmethod: username
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    socksmethod: username
    log: error
}
EOF

cat > "$INSTALL_DIR/dante/Dockerfile" <<'EOF'
FROM ubuntu:22.04
RUN apt-get update -qq && apt-get install -y -qq dante-server && rm -rf /var/lib/apt/lists/*
COPY danted.conf /etc/danted.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
EXPOSE 1080
ENTRYPOINT ["/entrypoint.sh"]
EOF

cat > "$INSTALL_DIR/dante/entrypoint.sh" <<'EOSH'
#!/bin/bash
# Создаём пользователя для SOCKS5
USER="${SOCKS_USER:-proxyuser}"
PASS="${SOCKS_PASS:-changeme}"
id "$USER" &>/dev/null || useradd -M -s /usr/sbin/nologin "$USER"
echo "$USER:$PASS" | chpasswd
exec danted -f /etc/danted.conf
EOSH
chmod +x "$INSTALL_DIR/dante/entrypoint.sh"

# ── Tinyproxy HTTP ────────────────────────
mkdir -p "$INSTALL_DIR/tinyproxy"

cat > "$INSTALL_DIR/tinyproxy/tinyproxy.conf" <<EOF
Port $HTTP_PORT
Listen 0.0.0.0
Timeout 600
DefaultErrorFile "/usr/share/tinyproxy/default.html"
StatFile "/usr/share/tinyproxy/stats.html"
LogLevel Info
MaxClients 100
MinSpareServers 5
MaxSpareServers 20
StartServers 10
MaxRequestsPerChild 0
Allow 0.0.0.0/0
ViaProxyName "tinyproxy"
EOF

# ── docker-compose.yml ────────────────────
cat > "$INSTALL_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  dante:
    build: ./dante
    container_name: dante-socks5
    restart: unless-stopped
    ports:
      - "${SOCKS_PORT}:${SOCKS_PORT}"
    environment:
      - SOCKS_USER=${SOCKS_USER}
      - SOCKS_PASS=${SOCKS_PASS}

  tinyproxy:
    image: vimagick/tinyproxy
    container_name: tinyproxy-http
    restart: unless-stopped
    ports:
      - "${HTTP_PORT}:${HTTP_PORT}"
    volumes:
      - ./tinyproxy/tinyproxy.conf:/etc/tinyproxy/tinyproxy.conf:ro
EOF

log "Конфиги созданы"

# ════════════════════════════════════════════
# 4. ЗАПУСК ПРОКСИ (Docker Compose)
# ════════════════════════════════════════════
info "Собираем и запускаем контейнеры прокси..."
cd "$INSTALL_DIR"

if docker compose version &>/dev/null 2>&1; then
    docker compose up -d --build
else
    docker-compose up -d --build
fi

log "Прокси запущены"

# ════════════════════════════════════════════
# 5. OUTLINE VPN
# ════════════════════════════════════════════
info "Устанавливаем Outline VPN..."
mkdir -p "$OUTLINE_DIR"

if [[ -f "$OUTLINE_DIR/access.txt" ]]; then
    warn "Outline уже установлен, пропускаем..."
else
    bash -c "$(wget -qO- https://raw.githubusercontent.com/Jigsaw-Code/outline-server/master/src/server_manager/install_scripts/install_server.sh)" \
        install_server.sh --keys-port=9999 2>&1 | tee /tmp/outline_install.log

    # Извлекаем данные подключения
    OUTLINE_API=$(grep "apiUrl" /tmp/outline_install.log | grep -o '"apiUrl":"[^"]*"' | cut -d'"' -f4)
    OUTLINE_CERT=$(grep "certSha256" /tmp/outline_install.log | grep -o '"certSha256":"[^"]*"' | cut -d'"' -f4)

    cat > "$OUTLINE_DIR/access.txt" <<EOF
{
  "apiUrl": "${OUTLINE_API}",
  "certSha256": "${OUTLINE_CERT}"
}
EOF
    log "Outline VPN установлен"
fi

# ════════════════════════════════════════════
# 6. ФАЙРВОЛ (UFW)
# ════════════════════════════════════════════
info "Настраиваем файрвол..."
ufw --force reset >/dev/null 2>&1
ufw default deny incoming >/dev/null 2>&1
ufw default allow outgoing >/dev/null 2>&1
ufw allow 22/tcp    >/dev/null 2>&1  # SSH
ufw allow "$SOCKS_PORT/tcp" >/dev/null 2>&1
ufw allow "$HTTP_PORT/tcp"  >/dev/null 2>&1
ufw allow 9999/tcp  >/dev/null 2>&1  # Outline keys port
ufw allow 443/tcp   >/dev/null 2>&1  # Outline HTTPS
ufw --force enable  >/dev/null 2>&1
log "Файрвол настроен"

# ════════════════════════════════════════════
# 7. СОХРАНЯЕМ SUMMARY
# ════════════════════════════════════════════
SUMMARY_FILE="$INSTALL_DIR/access-summary.txt"

cat > "$SUMMARY_FILE" <<EOF
════════════════════════════════════════════════
  proxy-stack — данные для подключения
  Сервер: $SERVER_IP
  Дата:   $(date '+%Y-%m-%d %H:%M:%S')
════════════════════════════════════════════════

SOCKS5 прокси (Dante):
  Хост:     $SERVER_IP
  Порт:     $SOCKS_PORT
  Логин:    $SOCKS_USER
  Пароль:   $SOCKS_PASS

HTTP прокси (Tinyproxy):
  Хост:     $SERVER_IP
  Порт:     $HTTP_PORT
  (без аутентификации, можно добавить BasicAuth)

Outline VPN:
  Управление: Outline Manager → вставь содержимое /opt/outline/access.txt
  Файл:        $OUTLINE_DIR/access.txt

════════════════════════════════════════════════
EOF

chmod 600 "$SUMMARY_FILE"

# ════════════════════════════════════════════
# 8. ИТОГОВЫЙ ВЫВОД
# ════════════════════════════════════════════
echo ""
echo -e "${BOLD}${GREEN}════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}   УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО              ${NC}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════${NC}"
echo ""
cat "$SUMMARY_FILE"
echo ""
echo -e "${CYAN}Данные сохранены в: ${BOLD}$SUMMARY_FILE${NC}"
echo ""

# Проверка статуса контейнеров
info "Статус контейнеров:"
docker ps --format "  {{.Names}}\t{{.Status}}\t{{.Ports}}"
echo ""
log "Готово! 🚀"
