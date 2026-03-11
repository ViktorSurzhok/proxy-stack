# proxy-stack-deploy

Автоматическая установка прокси + VPN на новый VPS одной командой.

## Что устанавливается

| Сервис | Протокол | Порт |
|---|---|---|
| **Dante** | SOCKS5 (с логином/паролем) | 1080 |
| **Tinyproxy** | HTTP прокси | 8888 |
| **Outline VPN** | Shadowsocks (управляется через Outline Manager) | 443 / 9999 |

Всё работает через **Docker**. Устанавливается на Ubuntu 22.04 / Debian 12.

---

## Быстрый старт (одна команда)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ViktorSurzhok/proxy-stack/main/install.sh)"
```

Или через git (рекомендуется):

```bash
apt update && apt install -y git && \
git clone https://github.com/ViktorSurzhok/proxy-stack.git /root/proxy-stack && \
cd /root/proxy-stack && \
chmod +x install.sh && \
sudo ./install.sh
```

---

## Переопределение параметров

Можно задать свои значения прямо в команде:

```bash
SOCKS_USER=myuser SOCKS_PASS='MyPass123!' sudo ./install.sh
```

```bash
SOCKS_PORT=1080 HTTP_PORT=8888 sudo ./install.sh
```

Доступные переменные:

| Переменная | По умолчанию | Описание |
|---|---|---|
| `SOCKS_USER` | `proxyuser` | Логин для SOCKS5 |
| `SOCKS_PASS` | случайный | Пароль для SOCKS5 |
| `SOCKS_PORT` | `1080` | Порт SOCKS5 |
| `HTTP_PORT` | `8888` | Порт HTTP прокси |
| `INSTALL_DIR` | `/opt/proxy-stack` | Директория установки |

---

## После установки

Данные подключения сохраняются в:

```
/opt/proxy-stack/access-summary.txt
```

Посмотреть:
```bash
cat /opt/proxy-stack/access-summary.txt
```

### Outline VPN

1. Скачай [Outline Manager](https://getoutline.org/get-started/)
2. Нажми "Add server" → "Advanced"
3. Вставь содержимое `/opt/outline/access.txt`

---

## Обновление / переустановка

```bash
cd /root/proxy-stack
git pull
sudo ./install.sh
```

---

## Управление контейнерами

```bash
cd /opt/proxy-stack

# Статус
docker compose ps

# Логи Dante
docker compose logs dante

# Перезапуск
docker compose restart

# Остановить всё
docker compose down
```

---

## Требования

- Ubuntu 22.04 / Debian 12
- Минимум 512 MB RAM
- Доступ root
- Чистый VPS (или с уже установленным Docker)
