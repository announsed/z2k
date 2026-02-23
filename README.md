# z2k v2.0 - Zapret2 для Keenetic (BETA VERSION)

Проект в активной разработке. Статус: beta version. Возможны баги и изменения.

Поддержать проект:

- TON: `UQA6Y6Mf1Qge2dVSl3_vSqb29SKrhI8VgJtoRBjgp08oB8QY`
- USDT (ERC20): `0xA1D6d7d339f05C1560ecAF0c5CB8c4dc80Dc46A9`

Если нужно максимально простое и проверенное решение, посмотрите также: https://github.com/IndeecFOX/zapret4rocket

**Важно:** после установки применяются autocircular стратегии. Им нужно время и несколько попыток, чтобы подстроиться под DPI. Если сайт не открывается сразу — дайте странице несколько раз перезагрузиться. Параметры перебираются автоматически, после чего сайт обычно начинает открываться.

---

## Что это

z2k — модульный установщик zapret2 для роутеров Keenetic с Entware.

Цель проекта: максимально упростить установку zapret2 на Keenetic и дать рабочий набор стратегий с автоподбором (autocircular) и поддержкой IPv6 там, где это возможно.

---

## Особенности

- Установка zapret2 (openwrt-embedded релиз) без компиляции, с проверкой работоспособности `nfqws2`
- Три TCP autocircular профиля с разными стратегиями (по 17 стратегий на категорию):
  - **RKN** — заблокированные сайты (TCP/TLS + HTTP)
  - **YouTube TCP** — youtube.com и связанные домены
  - **YouTube GV** — googlevideo CDN (стриминг)
- QUIC autocircular профиль: YouTube QUIC (UDP/443) по доменному списку
- Discord профили:
  - TCP: производится от RKN-стратегии с hostlist Discord
  - UDP voice/video: `circular_locked` (стратегия закрепляется per-domain через `locked.tsv`)
- Hostlist и autohostlist:
  - hostlist для выборочного применения (не "на весь интернет")
  - поддержка `--hostlist-auto` для TCP-профилей
- IPv6:
  - автоопределение доступности IPv6 и включение правил (iptables/ip6tables)
  - если IPv6 не поддерживается/не настроен — IPv6 правила не включаются
- Списки доменов устанавливаются автоматически (источник: zapret4rocket)

---

## Установка

### 1) Требования к прошивке Keenetic (обязательно)

Перед установкой zapret2 в веб-интерфейсе Keenetic нужно установить компоненты:

1. "Протокол IPv6"
2. "Модули ядра подсистемы Netfilter" (появляется только после выбора компонента "Протокол IPv6")

### 2) Подготовка USB и установка Entware (обязательно)

Подготовьте USB-накопитель и установите Entware по официальной инструкции Keenetic:
https://help.keenetic.com/hc/ru/articles/360021214160

После установки Entware выполните обновление индекса пакетов и установите зависимости:

```bash
opkg update
opkg install coreutils-sort curl grep gzip ipset iptables kmod_ndms xtables-addons_legacy
```

### 3) Установка z2k (Zapret2 для Keenetic)

```bash
curl -fsSL https://raw.githubusercontent.com/necronicle/z2k/master/z2k.sh | sh
```

---

## Что делает установщик

- Проверяет окружение (Entware, зависимости, архитектуру).
- Устанавливает zapret2 в `/opt/zapret2` и ставит init-скрипт `/opt/etc/init.d/S99zapret2`.
- Скачивает/обновляет доменные списки (YT, RKN, Discord).
- Генерирует и применяет autocircular стратегии для RKN / YouTube TCP / YouTube GV / QUIC / Discord.
- Включает IPv6 правила, если IPv6 реально доступен.

---

## Использование

### Повторный запуск / обновление

```bash
curl -fsSL https://raw.githubusercontent.com/necronicle/z2k/master/z2k.sh | sh
```

### Управление сервисом zapret2

```bash
/opt/etc/init.d/S99zapret2 start
/opt/etc/init.d/S99zapret2 stop
/opt/etc/init.d/S99zapret2 restart
/opt/etc/init.d/S99zapret2 status
```

### Обновление списков вручную

```bash
/opt/zapret2/ipset/get_config.sh
```

---

## Как работает autocircular

Каждый TCP/QUIC профиль содержит N стратегий с номерами `strategy=1..N`. Модуль `circular` в nfqws2 отслеживает успех/неудачу per-domain: после `fails=3` последовательных неудач домен переключается на следующую стратегию. Успешная стратегия закрепляется до следующей неудачи.

Для Discord UDP используется `circular_locked` — стратегия сохраняется в `locked.tsv` и не сбрасывается при перезапуске сервиса.

---

## Примечания

- Если вы используете IPv6 в сети, убедитесь что он включён в прошивке (см. требования выше).
- Если в системе нет `cron`, автообновление списков может быть недоступно — обновляйте списки вручную.

---

## Лицензия

MIT
