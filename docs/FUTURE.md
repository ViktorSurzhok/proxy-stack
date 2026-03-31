# Future improvements — proxy-stack

- **Healthcheck / smoke test**: отдельный `scripts/verify-remote.sh` с вашей рабочей машины (curl через Tinyproxy, проверка MTProto только на уровне TCP connect).
- **Cron для MTProto**: документированный таймер `docker restart proxy-stack-mtproto` или `compose restart`.
- **Поддержка SSH не на 22**: переменная `SSH_PORT` для UFW bootstrap.
- **IPv6**: явные правила UFW и `Allow` в Tinyproxy для v6-адресов клиентов.
- **Альтернатива MTProto-образу**: сборка из [TelegramMessenger/MTProxy](https://github.com/TelegramMessenger/MTProxy) или переход на поддерживаемый форк с регулярными обновлениями.
- **WireGuard** (или иной VPN) как отдельный необязательный профиль установки, вне базового стека Tinyproxy + MTProto.
- **Локализация логов**: опциональный `LANG=C` для стабильного парсинга вывода UFW.
