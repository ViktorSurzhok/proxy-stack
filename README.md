# proxy-stack

Чистый **личный** сетевой стек для VPS: **Tinyproxy** (HTTP-прокси для браузера), **MTProto Proxy** (Telegram в Docker), **UFW** с безопасными дефолтами, автогенерация секретов и человекочитаемая сводка после установки.

## Что входит

| Компонент   | Назначение                         | Как поднят        |
|------------|-------------------------------------|-------------------|
| Tinyproxy  | HTTP-прокси для браузера           | нативно (`apt`)   |
| MTProto    | прокси для Telegram                | Docker (`telegrammessenger/proxy`) |
| UFW        | файрвол, только помеченные правила | нативно           |

Точка входа: **`install.sh`**. Дополнительно: **`uninstall.sh`**, **`reconfigure.sh`**, **`update.sh`**.

Состояние и секреты по умолчанию: **`/opt/proxy-stack/`** (`secrets.env`, `summary.txt`, `install.log`, `docker/mtproto/`).

---

## Быстрая установка

**Где запускать:** только на **сервере** с Ubuntu/Debian (VPS по SSH). На **macOS или Windows** `install.sh` запускать не нужно: там нет `apt`, UFW и типичного `/etc/os-release` — скрипт для установки прямо на Linux-машине, которая будет прокси.

На новом Ubuntu VPS:

```bash
apt update && apt install -y git
git clone https://github.com/<you>/proxy-stack.git
cd proxy-stack
chmod +x install.sh uninstall.sh reconfigure.sh update.sh
sudo ./install.sh
```

Рекомендуется явно указать IP, с которых вы будете ходить в Tinyproxy (домашний/офисный публичный IP):

```bash
sudo ALLOWED_IPS=203.0.113.45 ./install.sh
```

Если вы подключены по SSH, скрипт попытается взять IP клиента из `SSH_CONNECTION` (удобно, но хрупко при NAT/прыгающем IP).

---

## Переменные окружения (install)

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `STATE_DIR` | `/opt/proxy-stack` | Каталог состояния |
| `TINYPROXY_PORT` | `8888` | Порт HTTP-прокси |
| `MTPROTO_PORT` | `443` | Публикуемый порт MTProto (внутри контейнера всегда 443) |
| `ALLOWED_IPS` | авто или обязательно | Список IP через запятую для Tinyproxy + UFW |
| `TINYPROXY_BASIC_AUTH_USER` / `TINYPROXY_BASIC_AUTH_PASS` | пусто | Опционально BasicAuth (вместе с ограничением по IP) |
| `CONFIRM_OPEN_PROXY` | — | Только со значением `I_UNDERSTAND_OPEN_PROXY_RISK` включает открытый прокси для всего мира (не рекомендуется) |

---

## Как проверить

1. **Сводка и секреты**

   ```bash
   sudo cat /opt/proxy-stack/summary.txt
   sudo ls -la /opt/proxy-stack/secrets.env
   ```

2. **Сервисы**

   ```bash
   systemctl status tinyproxy --no-pager
   docker ps --filter name=proxy-stack-mtproto
   sudo ufw status verbose
   ```

3. **Порты**

   ```bash
   sudo ss -tlnp | grep -E '8888|443|8443'
   ```

4. **Браузер**  
   Укажите **HTTP-прокси** `IP_СЕРВЕРА:8888` (не SOCKS). При BasicAuth введите логин/пароль из `secrets.env`.

5. **Telegram**  
   Откройте ссылку `https://t.me/proxy?...` из `summary.txt` или введите данные вручную.

---

## Как обновить (скрипты из git)

```bash
cd /path/to/proxy-stack
sudo ./update.sh
```

Это выполнит `git pull --ff-only` и снова запустит идемпотентный `install.sh`.

---

## Как переконфигурировать (IP / порты)

```bash
cd /path/to/proxy-stack
sudo ALLOWED_IPS_OVERRIDE=203.0.113.10,198.51.100.2 ./reconfigure.sh
```

Порты можно переопределить так же, как при установке (через переменные окружения перед `reconfigure.sh`), если они заданы в оболочке до запуска.

---

## Как удалить

```bash
cd /path/to/proxy-stack
sudo ./uninstall.sh
```

Опции:

- `PURGE_STATE=1` — удалить `/opt/proxy-stack`
- `REMOVE_MTDATA=1` — `docker compose down -v` (том MTProxy)

Пример:

```bash
sudo REMOVE_MTDATA=1 PURGE_STATE=1 ./uninstall.sh
```

---

## Документация

- [docs/SECURITY.md](docs/SECURITY.md) — заметки по безопасности  
- [docs/LIMITATIONS.md](docs/LIMITATIONS.md) — известные ограничения  
- [docs/FUTURE.md](docs/FUTURE.md) — идеи развития  

---

## Структура репозитория

```
install.sh
uninstall.sh
reconfigure.sh
update.sh
lib/
  common.sh
  firewall.sh
  tinyproxy.sh
  mtproto.sh
  verify.sh
docs/
  SECURITY.md
  LIMITATIONS.md
  FUTURE.md
README.md
```

---

## Лицензия и отказ от ответственности

Используйте только на своих серверах и в рамках политики хостера/закона. Авторы не несут ответственности за злоупотребления открытыми прокси и утечки секретов.
