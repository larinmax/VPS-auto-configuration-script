<div align="center">

# 🛡️ Автоматическая настройка VPS

**Интерактивный bash-скрипт для базовой настройки и защиты Linux-сервера**

Один запуск — и сервер обновлён, защищён, оптимизирован и очищен.

[![Bash](https://img.shields.io/badge/bash-5.0%2B-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20RHEL%20%7C%20CentOS%20%7C%20Fedora-FCC624?logo=linux&logoColor=black)](https://www.kernel.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](#лицензия)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](#вклад)

</div>

---

## 📖 Оглавление

- [Что это](#-что-это)
- [Возможности](#-возможности)
- [Требования](#-требования)
- [Быстрый старт](#-быстрый-старт)
- [Что спрашивает скрипт](#-что-спрашивает-скрипт)
- [Что делает скрипт](#-что-делает-скрипт)
- [На что обратить внимание](#-на-что-обратить-внимание)
- [Пример вывода](#-пример-вывода)
- [Важные предупреждения](#-важные-предупреждения)
- [Откат изменений](#-откат-изменений)
- [Логи](#-логи)
- [FAQ](#-faq)
- [Структура скрипта](#-структура-скрипта)
- [Лицензия](#лицензия)

---

## 🎯 Что это

`vps-setup.sh` — это интерактивный скрипт, который за один запуск приводит свежий Linux-сервер в «боевое» состояние:

- обновляет систему и чистит мусор,
- настраивает SSH (ключи, отключение пароля, hardening),
- ставит firewall, fail2ban, автообновления,
- оптимизирует сеть и лимиты,
- опционально отключает ICMP, IPv6 и ненужные службы,
- опционально устанавливает Docker Engine + Compose,
- настраивает ротацию логов и очистку диска.

Всё, что нужно — ответить на несколько вопросов в начале. Дальше скрипт работает молча и показывает только чек-лист статусов.

---

## ✨ Возможности

| Модуль | Что делает | Опционально |
|---|---|:---:|
| 🔄 **Обновление системы** | `apt upgrade` / `dnf update --security`, очистка кэша | — |
| 📦 **Базовые утилиты** | curl, wget, git, gnupg, lsb-release, **mc**, vim, nano, htop, iotop, iftop, rsync, net-tools, mtr и др. | ✅ |
| 🔐 **SSH hardening** | генерация ed25519-ключа, отключение пароля, смена порта, X11 off, MaxAuthTries, таймауты | ✅ |
| 🚫 **Fail2ban** | защита от брутфорса SSH с настраиваемыми параметрами бана | ✅ |
| 🔥 **Firewall** | UFW (Debian) / firewalld (RHEL), ввод разрешённых портов вручную; динамический SSH-порт | ✅ |
| 🔁 **Автообновления** | unattended-upgrades / dnf-automatic | ✅ |
| 🕒 **Timezone** | установка часового пояса и NTP | — |
| 💾 **Swap** | создание swap-файла 1GB, `vm.swappiness=10` | ✅ |
| ⚙️ **Sysctl** | защита сети, оптимизация TCP/IP | ✅ |
| 📊 **Лимиты** | nofile/nproc (по умолчанию 65535), настраиваемые значения | ✅ |
| 📡 **ICMP** | опциональное отключение пинга | ✅ |
| 🧹 **Очистка** | журналы, `/tmp`, кэш пакетов, старые ядра — с настраиваемым сроком хранения | — |
| 🛑 **Службы** | bluetooth, cups, avahi-daemon, ModemManager — по отдельности; IPv6 | ✅ |
| 🐳 **Docker** | Docker Engine + Compose из официального репозитория | ✅ |

---

## 📋 Требования

- **ОС:** Debian 11+, Ubuntu 20.04+, RHEL 8+, CentOS 8+, Fedora 35+ (или совместимые)
- **Bash:** 5.0+
- **Права:** root
- **Пакеты:** `systemd`, `openssh-server` (уже есть на большинстве серверов)
- **Свободное место:** ≥ 500 MB на `/var` (≥ 2 GB, если ставите Docker)
- **Интернет:** для установки пакетов и подключения репозитория Docker

---

## 🚀 Быстрый старт

### 1. Скачать скрипт

**Через curl:**

```bash
curl -L -f -O https://github.com/larinmax/VPS-auto-configuration-script/releases/download/vps-setup/vps-setup.sh
```

**Через wget:**

```bash
wget https://github.com/larinmax/VPS-auto-configuration-script/releases/download/vps-setup/vps-setup.sh
```

### 2. Сделать исполняемым

```bash
chmod +x vps-setup.sh
```

### 3. Запустить от root

```bash
sudo ./vps-setup.sh
```

### 4. Ответить на вопросы

Скрипт задаст ~20 вопросов (SSH-порт, что ставить, какие порты открыть, что отключать, ставить ли Docker, сколько хранить логи и т.д.). Все значения по умолчанию — разумные, можно просто нажимать Enter.

### 5. Проверить результат

Откройте **новое** окно терминала и зайдите по SSH, **не закрывая текущую сессию**:

```bash
ssh -p <порт> root@<IP>
```

---

## ❓ Что спрашивает скрипт

<details>
<summary><b>Развернуть полный список вопросов</b></summary>

**SSH:**
- Изменить SSH-порт? (Enter = 22)
- Отключить вход по паролю? (y/N)
- Вы уже проверили вход по ключу в новом окне? (yes/N)

**Утилиты:**
- Базовые (curl, wget, git, gnupg, lsb-release, **mc**)? (Y/n)
- Редакторы (vim, nano)? (Y/n)
- Мониторинг (htop, iotop, iftop)? (Y/n)
- Архивы (unzip, zip, rsync, tar)? (Y/n)
- Сеть (net-tools, dnsutils, traceroute, mtr, telnet)? (Y/n)

**Fail2ban:**
- Установить? (Y/n)
- Время бана, сек [86400]
- Попыток до бана [3]
- Окно наблюдения, сек [300]

**Firewall:**
- Настроить? (Y/n)
- Разрешённые TCP-порты [`<SSH_PORT>` 80 443]
  - Подсказка динамическая: если SSH-порт = 22 → `[22 80 443]`, если 12500 → `[12500 80 443]`.
  - При SSH-порте ≠ 22 порт 22 автоматически убирается из списка (если не введён явно).

**Автообновления:**
- Включить? (Y/n)

**Время:**
- Часовой пояс [UTC]

**Swap:**
- Создать swap-файл 1GB? (y/N)

**Sysctl:**
- Применить настройки безопасности сети? (Y/n)

**Лимиты:**
- Настроить? (Y/n)
- nofile [65535]
- nproc [65535]

**ICMP:**
- Отключить пинг? (y/N)

**Очистка:**
- Сколько дней хранить логи? [14]

**Службы:**
- bluetooth отключить? (Y/n)
- cups отключить? (Y/n)
- avahi-daemon отключить? (Y/n)
- ModemManager отключить? (Y/n)
- Отключить IPv6? (y/N)

**Docker:**
- Установить Docker Engine + Compose? (y/N)

</details>

---

## 🔧 Что делает скрипт

### 1. Обновление системы
- `apt update && apt upgrade` или `dnf update --security` — **интерактивно**, диалоги apt видны на экране.
- Перед обновлением `configure_debconf()` глушит лишние диалоги (раскладка клавиатуры, needrestart, apt-listchanges).
- После завершения — `clear` и короткая шапка «Продолжаю настройку».
- `autoremove`, `autoclean`, `clean all` — в фоне, с логом.

### 2. Установка утилит (по выбору)
Пакеты разбиты на категории — можно отказаться от любой:

| Категория | Пакеты |
|---|---|
| Базовые | curl, wget, git, ca-certificates, gnupg, lsb-release, **mc** |
| Редакторы | vim, nano |
| Мониторинг | htop, iotop, iftop |
| Архивы | unzip, zip, rsync, tar |
| Сеть | net-tools, dnsutils/bind-utils, traceroute, mtr, telnet |

### 3. SSH hardening
- Генерирует `ed25519` ключ (если его нет) и добавляет публичную часть в `authorized_keys`, **сохраняя чужие ключи** (например, провайдерские).
- **Сохраняет копию приватного ключа** в `/root/PRIVATE_KEY.txt` (chmod 600) — чтобы можно было скопировать позже.
- Выводит приватный ключ на экран (один раз, при генерации).
- Правит `/etc/ssh/sshd_config` и создаёт `/etc/ssh/sshd_config.d/99-hardening.conf`, который **перекрывает cloud-init drop-in**.
- **`UsePAM yes`** — критически важно, иначе вход по ключу сломается.
- **`PubkeyAuthentication yes`** — явно.
- Отключает X11, ограничивает MaxAuthTries, ставит таймауты.
- Опционально отключает пароль (с проверкой, что вход по ключу работает).
- Перезапускает правильный юнит: `ssh` или `sshd` (определяется автоматически).

### 4. Fail2ban (по выбору)
- Ставит `fail2ban`, пишет `/etc/fail2ban/jail.local` с настраиваемыми параметрами.

### 5. Firewall (по выбору)
- UFW (Debian) или firewalld (RHEL).
- Deny incoming, allow outgoing.
- **Логика портов:**
  - Подсказка динамическая: `22 80 443` при SSH-порте 22, `SSH_PORT 80 443` при другом.
  - Если SSH-порт ≠ 22 → порт 22 **автоматически удаляется** из списка (кроме случая, когда вы указали его явно).
  - Фактический SSH-порт всегда добавляется принудительно — защита от локаута.
- Порты валидируются (только числа 1..65535).

**Примеры:**

| SSH-порт | Ввод | UFW откроет |
|---|---|---|
| 22 | пусто | `22 80 443` |
| 22 | `80 443` | `80 443 22` |
| 12500 | пусто | `12500 80 443` |
| 12500 | `22 80 443` | `22 80 443 12500` |
| 12500 | `8080 9000` | `8080 9000 12500` |

### 6. Автообновления (по выбору)
- `unattended-upgrades` (Debian) или `dnf-automatic` (RHEL).

### 7. Timezone
- `timedatectl set-timezone`, NTP включён.

### 8. Swap (по выбору)
- 1GB swap-файл, `vm.swappiness=10`, запись в `/etc/fstab`.

### 9. Sysctl (по выбору)
- Защита сети: rp_filter, syncookies, ignore redirects, log_martians.
- Оптимизация TCP/IP: somaxconn, keepalive, fin_timeout, rmem/wmem.

### 10. Лимиты (по выбору)
- `nofile`, `nproc` — настраиваемые значения (по умолчанию 65535).
- Пишет в `/etc/security/limits.d/` и `/etc/systemd/system.conf.d/`.

### 11. ICMP (по выбору)
- `net.ipv4.icmp_echo_ignore_all` — 0 или 1.

### 12. Очистка логов и мусора
- Спрашивает срок хранения (по умолчанию 14 дней).
- journald: `SystemMaxUse=500M`, `MaxRetentionSec=Nd`, vacuum.
- logrotate: обновляет `rotate N` / `maxage N`.
- `/var/log`: удаляет `*.log`, `*.gz`, `*.old` старше N дней.
- `/tmp`, `/var/tmp`: файлы старше N дней.
- Кэш пакетов: `apt autoremove`/`dnf autoremove`, `apt autoclean`/`dnf clean all`.
- Старые ядра (Debian): оставляет текущее + одно предыдущее.
- `/var/cache/apt/archives` и `/var/cache/dnf`: старые файлы.

### 13. Службы и IPv6 (по выбору)
- **Каждая служба отключается отдельно** — bluetooth, cups, avahi-daemon, ModemManager.
- Используется `stop + disable + mask` (для полного запрета запуска).
- Службы, которых нет в системе, попадают в `notfound_list` — это нормально.
- Опционально отключается IPv6.

### 14. Docker Engine + Compose (по выбору)
- Подключает **официальный репозиторий** Docker (не `get.docker.com`).
- **Debian/Ubuntu:** новый формат `.sources` с `Signed-By`, GPG-ключ в `/etc/apt/keyrings/docker.asc`.
- **RHEL/CentOS/Fedora:** репозиторий через `dnf config-manager`.
- Ставит: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
- Удаляет конфликтующие пакеты (`docker.io`, `podman-docker`, `runc` и др.).
- Включает и запускает `docker.service`.
- Добавляет `root` в группу `docker`.
- Показывает версию и **предупреждает про обход ufw**.

---

## ⚠️ На что обратить внимание

### 🐳 Docker

> **Docker обходит правила ufw.** Контейнеры, опубликованные через `-p 8080:80`, становятся доступны извне **независимо от `ufw deny incoming`**. Docker вставляет свои правила в цепочку `DOCKER-USER`, которая обрабатывается раньше цепочек ufw.

Способы решения:
1. Публиковать на localhost: `-p 127.0.0.1:8080:80`.
2. Использовать [ufw-docker](https://github.com/chaifeng/ufw-docker).
3. Вручную добавлять правила в `DOCKER-USER`:
   ```bash
   iptables -I DOCKER-USER -i eth0 ! -s 1.2.3.4 -j DROP
   ```

> **Docker ставится из официального репозитория**, а не через `get.docker.com`. Это production-способ: контроль версий, штатные `apt upgrade`, автоматические обновления безопасности.

> **Старые пакеты удаляются.** Если у вас был `docker.io` (Debian-пакет) или `podman-docker`, они будут удалены перед установкой `docker-ce`. Контейнеры и образы при этом сохраняются (в `/var/lib/docker`), но способ управления меняется.

### 🔥 Firewall

> **Порт 22 автоматически заменяется на новый SSH-порт.** Если вы указали SSH-порт 12500, UFW откроет `12500 80 443`, а 22 — не будет (если вы не ввели его явно).

> **Если хотите оставить 22 открытым** — введите его явно: например `22 80 443`. Тогда даже при SSH-порте 12500 UFW откроет и 22, и 12500.

> **SSH-порт добавляется принудительно**, даже если вы забыли его указать в списке. Это защита от локаута.

### 🛑 Отключение служб

> **`mask` — более жёсткая мера, чем `disable`.** Замаскированную службу нельзя запустить даже вручную (только `unmask`). Это защищает от случайного запуска через зависимости. Если хотите только `disable` без `mask` — уберите строку в функции `disable_services()`.

> **`cups`** иногда нужен, если вы печатаете с сервера или используете его как print-сервер. На обычном VPS — не нужен.

> **`avahi-daemon`** может использоваться для обнаружения сервисов в локальной сети (mDNS). Если сервер в изолированной сети и вы не используете `.local` имена — отключайте смело.

> **`ModemManager`** часто отсутствует на VPS, тогда попадёт в `notfound_list` — это нормально.

> **IPv6** — если провайдер выдаёт IPv6-адрес и вы им пользуетесь, оставьте `N`. Если не знаете, используется ли — можно проверить:
> ```bash
> ip -6 addr show scope global | grep inet6
> ```

### 🔐 SSH

> **`UsePAM no` ломает вход по ключу** на Ubuntu/Debian. Скрипт всегда ставит `yes`. Если правите вручную — не забудьте.

> **Drop-in конфиги** в `/etc/ssh/sshd_config.d/` (например, `50-cloud-init.conf`) могут перекрывать основной `sshd_config`. Скрипт создаёт `99-hardening.conf`, который читается последним.

> **Приватный ключ сохраняется в двух местах:** `/root/.ssh/id_ed25519` и `/root/PRIVATE_KEY.txt`. Скопируйте на клиента и удалите копию: `shred -u /root/PRIVATE_KEY.txt`.

### 🧹 Очистка

> **Старые ядра удаляются** (Debian) — оставляется текущее и одно предыдущее. Если у вас кастомный бутлоадер — проверьте перед запуском.

> **Срок хранения логов** влияет на дисковое пространство и возможность отладки. 7 дней — минимум места, но без истории; 90 — для аудита. По умолчанию 14 — компромисс.

### 💾 Swap

> **Если swap уже есть**, скрипт его не трогает — просто пропускает шаг. Создание возможно только на чистом сервере.

### 📡 ICMP

> **Отключение пинга** может сломать мониторинг провайдера (uptime-проверки). Уточните политику перед отключением.

---

## 🖥️ Пример вывода

```
╔══════════════════════════════════════════════════════════╗
║      Настройка сервера — ответьте на несколько вопросов  ║
╚══════════════════════════════════════════════════════════╝

Enter = значение по умолчанию (в скобках)

── SSH ──
  Изменить SSH-порт (Enter = 22):
  Отключить вход по паролю (только ключи)? (y/N):
  Вы уже проверили вход по ключу в новом окне? (yes/N):
...

── Docker ──
  Установка из официального репозитория (docker-ce + compose-plugin).
  Внимание: Docker обходит правила ufw — учитывайте при публикации портов.
  Установить Docker Engine + Compose? (y/N):
...

══════════════════════════════════════════════════════════
Все параметры собраны. Начинаю настройку...
══════════════════════════════════════════════════════════

[ 1/14] Обновление системы
        └─ OK
[ 2/14] Установка базовых утилит
        └─ OK
[ 3/14] Настройка SSH
        └─ OK
[ 4/14] Fail2ban
        └─ OK
[ 5/14] Firewall
        └─ OK
[ 6/14] Автоматические обновления
        └─ OK
[ 7/14] Часовой пояс
        └─ OK
[ 8/14] Swap
        └─ SKIP
[ 9/14] Sysctl (сеть/TCP)
        └─ OK
[10/14] Системные лимиты
        └─ OK
[11/14] ICMP (ping)
        └─ SKIP
[12/14] Очистка логов и мусора
        └─ OK
[13/14] Отключение служб и IPv6
        └─ OK
[14/14] Docker Engine + Compose
        └─ OK

╔══════════════════════════════════════════════════════════╗
║                    ИТОГИ НАСТРОЙКИ                       ║
╚══════════════════════════════════════════════════════════╝

Выполненные действия:
  1. Система обновлена и очищена
  2. Установлены утилиты (базовые редакторы мониторинг архивы сеть)
  ...
  14. Docker: Docker version 27.x.x, build ...

──────────────────────────────────────────────────────────
Статус подсистем:

  Firewall:  Status: active
  Fail2ban:  active
  Swap:      /swapfile 1G
  Timezone:  Europe/Moscow
  NTP:       yes
  ICMP:      разрешён
  Docker:    Docker version 27.x.x

  UsePAM:                yes
  PasswordAuthentication: no
  PubkeyAuthentication:   yes
  PermitRootLogin:        prohibit-password
  Ключей в authorized_keys: 2
  Свободно на /: 38G (12% занято)

──────────────────────────────────────────────────────────
  Полный лог: /var/log/setup-server.log
──────────────────────────────────────────────────────────
```

---

## ⚠️ Важные предупреждения

> **Перед запуском на боевом сервере сделайте снапшот VPS или бэкап.**

> **Убедитесь, что у вас есть доступ к консоли провайдера (KVM/VNC).** Если SSH отвалится — вернуть доступ можно только через неё.

> **Проверяйте вход по ключу в НОВОМ окне**, не закрывая текущую сессию. Скрипт спрашивает подтверждение перед отключением пароля — отвечайте `yes` только после реальной проверки.

> **Сохраните приватный ключ.** Копия лежит в `/root/PRIVATE_KEY.txt`. После копирования удалите её: `shred -u /root/PRIVATE_KEY.txt`.

> **Docker обходит ufw.** Публикация портов контейнеров делается вне правил ufw. См. раздел «На что обратить внимание».

> **ICMP-пинг** может использоваться провайдером для мониторинга. Уточните политику перед отключением.

> **Старые ядра** удаляются — оставляется текущее и одно предыдущее. Если у вас кастомный бутлоадер — проверьте перед запуском.

---

## 🔄 Откат изменений

### SSH-конфиг
```bash
ls -la /etc/ssh/sshd_config.bak.*
cp /etc/ssh/sshd_config.bak.<timestamp> /etc/ssh/sshd_config
rm -f /etc/ssh/sshd_config.d/99-hardening.conf
systemctl restart ssh   # или sshd
```

### authorized_keys
```bash
ls -la /root/.ssh/authorized_keys.bak.*
cp /root/.ssh/authorized_keys.bak.<timestamp> /root/.ssh/authorized_keys
```

### Firewall
```bash
# UFW
ufw disable
# или firewalld
systemctl stop firewalld
```

### Службы
```bash
systemctl unmask bluetooth cups avahi-daemon ModemManager
systemctl enable bluetooth    # если нужно
systemctl start bluetooth
```

### Sysctl / ICMP / IPv6 / Лимиты
```bash
rm -f /etc/sysctl.d/99-hardening.conf
rm -f /etc/sysctl.d/99-disable-icmp.conf
rm -f /etc/sysctl.d/99-disable-ipv6.conf
rm -f /etc/security/limits.d/99-hardening.conf
rm -f /etc/systemd/system.conf.d/99-limits.conf
sysctl --system
systemctl daemon-reexec
```

### Docker
```bash
# Остановить и удалить
systemctl stop docker
apt remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# или
dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Удалить репозиторий
rm -f /etc/apt/sources.list.d/docker.sources
rm -f /etc/apt/keyrings/docker.asc
# или
rm -f /etc/yum.repos.d/docker-ce.repo

# Удалить данные (образы, контейнеры, тома)
rm -rf /var/lib/docker /var/lib/containerd
```

---

## 📝 Логи

Все детальные выводы команд пишутся в:

```
/var/log/setup-server.log
```

Если что-то пошло не так — смотрите туда. На экран выводятся только статусы (OK/SKIP/FAIL), спиннер во время операций и итоговый отчёт.

Посмотреть хвост:

```bash
tail -50 /var/log/setup-server.log
```

Или поискать ошибки:

```bash
grep -iE "error|fail|denied" /var/log/setup-server.log
```

---

## ❔ FAQ

<details>
<summary><b>Не заходит по SSH после отключения пароля</b></summary>

Через консоль провайдера:

```bash
rm -f /etc/ssh/sshd_config.d/99-hardening.conf
cp /etc/ssh/sshd_config.bak.* /etc/ssh/sshd_config
systemctl restart ssh
```

Проверьте, что в `/root/.ssh/authorized_keys` есть **ваш** публичный ключ, а отпечаток совпадает:

```bash
ssh-keygen -lf /root/.ssh/authorized_keys       # на сервере
ssh-keygen -lf ~/.ssh/id_ed25519.pub            # на клиенте
```

</details>

<details>
<summary><b>Почему <code>PasswordAuthentication no</code> не применяется?</b></summary>

Скорее всего, перекрывает drop-in файл в `/etc/ssh/sshd_config.d/`, например `50-cloud-init.conf`. Проверьте:

```bash
sshd -T | grep -i passwordauth
grep -rn -i passwordauth /etc/ssh/sshd_config.d/
```

Скрипт создаёт `99-hardening.conf`, который читается **последним** и перекрывает всё. Если его нет — создайте или отредактируйте облачный drop-in.

</details>

<details>
<summary><b>Не работает вход по ключу, ошибка <code>UsePAM no</code></b></summary>

Это классическая ошибка. На Ubuntu/Debian `UsePAM no` ломает вход по ключу. Проверьте:

```bash
sshd -T | grep -i usepam   # должно быть yes
```

Исправить:

```bash
sed -i 's/^#\?UsePAM .*/UsePAM yes/' /etc/ssh/sshd_config
systemctl restart ssh
```

Скрипт всегда ставит `UsePAM yes`.

</details>

<details>
<summary><b>Firewall заблокировал SSH</b></summary>

Через консоль провайдера:

```bash
ufw allow <SSH_PORT>/tcp
ufw reload
# или
firewall-cmd --permanent --add-port=<SSH_PORT>/tcp
firewall-cmd --reload
```

Скрипт добавляет фактический SSH-порт принудительно, так что после настройки он должен быть открыт. Если вы потом вручную удалили правило — верните его командой выше.

</details>

<details>
<summary><b>Firewall открыл не те порты, которые я ожидал</b></summary>

Проверьте активные правила:

```bash
ufw status numbered
# или
firewall-cmd --list-all
```

Логика скрипта:
- Подсказка динамическая: если SSH-порт = 22 → `22 80 443`, если 12500 → `12500 80 443`.
- Если SSH-порт ≠ 22 и вы не ввели `22` явно → порт 22 удаляется из списка.
- Если хотите оставить 22 — вводите его **явно**: `22 80 443`.

Посмотреть, что именно выполнил скрипт:

```bash
grep -A5 "настройка ufw" /var/log/setup-server.log
```

</details>

<details>
<summary><b>Docker не видит контейнеры / <code>docker ps</code> требует sudo</b></summary>

Скрипт добавляет `root` в группу `docker`, но это применяется только в **новой** сессии. Выйдите и зайдите снова, или выполните:

```bash
newgrp docker
```

Проверить:

```bash
docker ps
docker compose version
```

</details>

<details>
<summary><b>Порты контейнеров открыты извне, хотя ufw стоит в deny</b></summary>

Это ожидаемое поведение Docker. Он добавляет правила в iptables через цепочку `DOCKER-USER`, которая обрабатывается раньше правил ufw.

Решения:
1. Публикуйте на `127.0.0.1`: `-p 127.0.0.1:8080:80`.
2. Используйте [ufw-docker](https://github.com/chaifeng/ufw-docker).
3. Вручную ограничьте доступ в цепочке `DOCKER-USER`.

</details>

<details>
<summary><b>Где взять приватный ключ, который был выведен на экран?</b></summary>

Скрипт сохраняет копию в `/root/PRIVATE_KEY.txt`. Посмотреть:

```bash
cat /root/PRIVATE_KEY.txt
```

Скопировать на клиента:

```bash
scp root@<IP>:/root/PRIVATE_KEY.txt ~/.ssh/id_ed25519
chmod 600 ~/.ssh/id_ed25519
```

После успешного копирования удалить:

```bash
shred -u /root/PRIVATE_KEY.txt
```

</details>

<details>
<summary><b>Как вернуть отключённую службу?</b></summary>

Службы маскируются через `systemctl mask`, поэтому просто `enable` не поможет. Нужно сначала размаскировать:

```bash
systemctl unmask bluetooth
systemctl enable --now bluetooth
```

Проверить, что служба в порядке:

```bash
systemctl status bluetooth
```

</details>

<details>
<summary><b>Скрипт можно запускать повторно?</b></summary>

Да. Все операции идемпотентны:
- обновление — безопасно,
- утилиты — переустановка не ломает,
- SSH-конфиг — делает бэкап и правит,
- firewall — сбрасывает и настраивает заново,
- лимиты, sysctl, swap — перезаписываются,
- службы — повторное отключение безопасно,
- IPv6 всегда пишется либо `1`, либо `0` (защита от «залипшего» состояния),
- Docker — повторная установка не ломает (пакеты уже стоят, репозиторий уже подключён).

Повторный запуск с теми же ответами ничего не сломает.

</details>

<details>
<summary><b>Скрипт поддерживает Rocky Linux / AlmaLinux?</b></summary>

Да, они определяются как `redhat`-семейство (`/etc/redhat-release`). Используется `dnf` и `firewalld`.

</details>

<details>
<summary><b>Что такое спиннер в выводе?</b></summary>

Во время длительных
