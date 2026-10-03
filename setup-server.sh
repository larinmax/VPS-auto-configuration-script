#!/bin/bash
set -euo pipefail

# ============================================================
#  Скрипт базовой настройки и защиты Linux-сервера
#  Стиль: предварительный опрос → чек-лист → отчёт
#  Лог: /var/log/setup-server.log
# ============================================================

# --- Цвета ---
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; C='\033[0;36m'; D='\033[0;90m'; N='\033[0m'; B='\033[1m'

# --- Лог-файл ---
LOG_FILE="/var/log/setup-server.log"
: > "$LOG_FILE"
exec 3>&1   # FD 3 — оригинальный stdout (для интерактива)

# --- Счётчик шагов ---
STEP=0
TOTAL_STEPS=13

# --- Печать строки шага ---
step() {
    STEP=$((STEP+1))
    printf "${C}[%2d/%d]${N} %-42s" "$STEP" "$TOTAL_STEPS" "$1"
}

ok()   { printf "${G}OK${N}\n"; }
skip() { printf "${Y}SKIP${N}\n"; }
fail() { printf "${R}FAIL${N}\n"; }

# --- Спиннер (для операций, пишущих в лог) ---
SPINNER_PID=""
start_spinner() {
    local msg="${1:-}"
    (
        local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        local i=0
        while true; do
            i=$(( (i+1) % 10 ))
            printf "\r  ${C}%s${N} ${D}%s${N}" "${spin:$i:1}" "$msg" >&3
            sleep 0.1
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}

stop_spinner() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null || true
        wait "$SPINNER_PID" 2>/dev/null || true
        printf "\r\033[K" >&3
        SPINNER_PID=""
    fi
}

# --- Обёртка: запускает команду в фоне с логом и спиннером ---
run_quiet() {
    local msg="$1"; shift
    "$@" >> "$LOG_FILE" 2>&1 &
    local cmd_pid=$!
    start_spinner "$msg"
    local rc=0
    wait "$cmd_pid" || rc=$?
    stop_spinner
    return $rc
}

# --- Проверка root ---
if [[ $EUID -ne 0 ]]; then
   echo -e "${R}Скрипт нужно запускать от root (sudo su - или sudo ./vps-setup.sh)${N}"
   exit 1
fi

# --- Определение дистрибутива ---
if [[ -f /etc/debian_version ]]; then
    OS_FAMILY="debian"
elif [[ -f /etc/redhat-release ]]; then
    OS_FAMILY="redhat"
else
    echo -e "${R}Неподдерживаемый дистрибутив. Нужен Debian/Ubuntu или RHEL/CentOS/Fedora.${N}"
    exit 1
fi

# --- Определение юнита SSH ---
SSH_RESTART_UNIT="ssh"
detect_ssh_unit() {
    if systemctl list-unit-files | grep -q '^sshd.service'; then
        SSH_RESTART_UNIT="sshd"
    else
        SSH_RESTART_UNIT="ssh"
    fi
}
restart_ssh() { systemctl restart "$SSH_RESTART_UNIT" >> "$LOG_FILE" 2>&1; }

# --- Массив отчёта ---
declare -a REPORT
report() { REPORT+=("$1"); }

# --- Статусы подсистем ---
FIREWALL_ENABLED="no"
FAIL2BAN_ENABLED="no"
ICMP_DISABLED="no"
LIMITS_NOFILE=""
LIMITS_NPROC=""
LOG_RETENTION_DAYS=""

# ============================================================
#  Подготовка debconf
# ============================================================
configure_debconf() {
    if command -v debconf-set-selections >/dev/null 2>&1; then
        echo "keyboard-configuration keyboard-configuration/layoutcode select us" | debconf-set-selections 2>/dev/null || true
        echo "keyboard-configuration keyboard-configuration/model select Generic 105-key PC" | debconf-set-selections 2>/dev/null || true
        echo "keyboard-configuration keyboard-configuration/xkb-keymap select us" | debconf-set-selections 2>/dev/null || true
    fi

    export NEEDRESTART_MODE=a
    if [[ -f /etc/needrestart/needrestart.conf ]]; then
        if grep -q '^\s*#\?\$nrconf{restart}' /etc/needrestart/needrestart.conf 2>/dev/null; then
            sed -i "s|^\s*#\?\$nrconf{restart}.*|\$nrconf{restart} = 'a';|" /etc/needrestart/needrestart.conf 2>/dev/null || true
        else
            echo "\$nrconf{restart} = 'a';" >> /etc/needrestart/needrestart.conf 2>/dev/null || true
        fi
    fi

    if [[ -f /etc/apt/apt.conf.d/20listchanges ]]; then
        sed -i 's/^\(.*\)apt-listchanges\(.*\)$/#\1apt-listchanges\2 # отключено скриптом/' \
            /etc/apt/apt.conf.d/20listchanges 2>/dev/null || true
    fi
}

# ============================================================
#  ПРЕДВАРИТЕЛЬНЫЙ ОПРОС
# ============================================================
echo ""
echo -e "${C}╔══════════════════════════════════════════════════════════╗${N}"
echo -e "${C}║      Настройка сервера — ответьте на несколько вопросов  ║${N}"
echo -e "${C}╚══════════════════════════════════════════════════════════╝${N}"
echo ""
echo -e "${D}Enter = значение по умолчанию (в скобках)${N}"
echo ""

# --- SSH ---
echo -e "${B}── SSH ──${N}"
read -rp "  Изменить SSH-порт (Enter = 22): " SSH_PORT
SSH_PORT="${SSH_PORT:-22}"
if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo -e "  ${Y}Некорректный порт, будет использован 22.${N}"
    SSH_PORT=22
fi

read -rp "  Отключить вход по паролю (только ключи)? (y/N): " DISABLE_PASS
read -rp "  Вы уже проверили вход по ключу в новом окне? (yes/N): " CHECK_KEY_OK

# --- Утилиты ---
echo ""
echo -e "${B}── Утилиты (что устанавливать) ──${N}"
read -rp "  Базовые (curl, wget, git, gnupg, lsb-release)? (Y/n): " INSTALL_BASE
read -rp "  Редакторы (vim, nano)? (Y/n): " INSTALL_EDITORS
read -rp "  Мониторинг (htop, iotop, iftop)? (Y/n): " INSTALL_MONITORING
read -rp "  Архивы (unzip, zip, rsync, tar)? (Y/n): " INSTALL_ARCHIVE
read -rp "  Сеть (net-tools, dnsutils, traceroute, mtr, telnet)? (Y/n): " INSTALL_NET
[[ -z "$INSTALL_BASE" ]]       && INSTALL_BASE="y"
[[ -z "$INSTALL_EDITORS" ]]    && INSTALL_EDITORS="y"
[[ -z "$INSTALL_MONITORING" ]] && INSTALL_MONITORING="y"
[[ -z "$INSTALL_ARCHIVE" ]]    && INSTALL_ARCHIVE="y"
[[ -z "$INSTALL_NET" ]]        && INSTALL_NET="y"

# --- Fail2ban ---
echo ""
echo -e "${B}── Fail2ban ──${N}"
read -rp "  Установить и настроить fail2ban? (Y/n): " WANT_F2B
[[ -z "$WANT_F2B" ]] && WANT_F2B="y"
if [[ "$WANT_F2B" =~ ^[Yy]$ ]]; then
    read -rp "    Время бана, сек [86400]: " F2B_BANTIME
    read -rp "    Попыток до бана [3]: " F2B_MAXRETRY
    read -rp "    Окно наблюдения, сек [300]: " F2B_FINDTIME
    F2B_BANTIME="${F2B_BANTIME:-86400}"
    F2B_MAXRETRY="${F2B_MAXRETRY:-3}"
    F2B_FINDTIME="${F2B_FINDTIME:-300}"
fi

# --- Firewall ---
echo ""
echo -e "${B}── Firewall ──${N}"
read -rp "  Настроить firewall (ufw/firewalld)? (Y/n): " WANT_FW
[[ -z "$WANT_FW" ]] && WANT_FW="y"
if [[ "$WANT_FW" =~ ^[Yy]$ ]]; then
    # Показываем фактический SSH-порт вместо 22, если он изменён
    if [[ "$SSH_PORT" == "22" ]]; then
        FW_DEFAULT_PORTS="22 80 443"
    else
        FW_DEFAULT_PORTS="$SSH_PORT 80 443"
    fi
    read -rp "    Разрешённые TCP-порты [$FW_DEFAULT_PORTS]: " PORTS_INPUT
fi

# --- Автообновления ---
echo ""
echo -e "${B}── Автообновления ──${N}"
read -rp "  Включить автообновления безопасности? (Y/n): " WANT_AUTO
[[ -z "$WANT_AUTO" ]] && WANT_AUTO="y"

# --- Timezone ---
echo ""
echo -e "${B}── Время ──${N}"
read -rp "  Часовой пояс (например Europe/Moscow) [UTC]: " TZ
TZ="${TZ:-UTC}"

# --- Swap ---
echo ""
echo -e "${B}── Swap ──${N}"
read -rp "  Создать swap-файл 1GB (если ещё нет)? (y/N): " WANT_SWAP

# --- Sysctl ---
echo ""
echo -e "${B}── Sysctl (сеть/TCP) ──${N}"
read -rp "  Применить настройки безопасности и оптимизации сети? (Y/n): " WANT_SYSCTL
[[ -z "$WANT_SYSCTL" ]] && WANT_SYSCTL="y"

# --- Лимиты ---
echo ""
echo -e "${B}── Лимиты системы ──${N}"
read -rp "  Настроить лимиты (nofile, nproc)? (Y/n): " WANT_LIMITS
[[ -z "$WANT_LIMITS" ]] && WANT_LIMITS="y"
if [[ "$WANT_LIMITS" =~ ^[Yy]$ ]]; then
    read -rp "    nofile [65535]: " LIMITS_NOFILE
    read -rp "    nproc  [65535]: " LIMITS_NPROC
    LIMITS_NOFILE="${LIMITS_NOFILE:-65535}"
    LIMITS_NPROC="${LIMITS_NPROC:-65535}"
    [[ "$LIMITS_NOFILE" =~ ^[0-9]+$ ]] || LIMITS_NOFILE=65535
    [[ "$LIMITS_NPROC"  =~ ^[0-9]+$ ]] || LIMITS_NPROC=65535
fi

# --- ICMP ---
echo ""
echo -e "${B}── ICMP (ping) ──${N}"
read -rp "  Отключить ICMP-эхо (ping) полностью? (y/N): " WANT_NOICMP

# --- Очистка логов ---
echo ""
echo -e "${B}── Очистка логов и мусора ──${N}"
echo -e "  ${D}7 — минимум места, 14 — компромисс, 30 — стандарт, 90 — аудит${N}"
read -rp "  Сколько дней хранить логи? [14]: " LOG_RETENTION_DAYS
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-14}"
[[ "$LOG_RETENTION_DAYS" =~ ^[0-9]+$ ]] || LOG_RETENTION_DAYS=14
[[ "$LOG_RETENTION_DAYS" -lt 1 ]] && LOG_RETENTION_DAYS=14

# --- Отключение служб ---
echo ""
echo -e "${B}── Отключение ненужных служб ──${N}"
echo -e "  ${D}Обычно на сервере не нужны. Enter = значение по умолчанию.${N}"
read -rp "  bluetooth (Bluetooth-стек)? (Y/n): " WANT_NO_BLUETOOTH
read -rp "  cups (сервер печати)? (Y/n): " WANT_NO_CUPS
read -rp "  avahi-daemon (mDNS/DNS-SD, часто не нужен)? (Y/n): " WANT_NO_AVAHI
read -rp "  ModemManager (управление модемами)? (Y/n): " WANT_NO_MODEM
read -rp "  Отключить IPv6? (y/N): " WANT_NOIPV6
[[ -z "$WANT_NO_BLUETOOTH" ]] && WANT_NO_BLUETOOTH="y"
[[ -z "$WANT_NO_CUPS" ]]      && WANT_NO_CUPS="y"
[[ -z "$WANT_NO_AVAHI" ]]     && WANT_NO_AVAHI="y"
[[ -z "$WANT_NO_MODEM" ]]     && WANT_NO_MODEM="y"

# --- Итог опроса ---
echo ""
echo -e "${C}══════════════════════════════════════════════════════════${N}"
echo -e "${G}Все параметры собраны. Начинаю настройку...${N}"
echo -e "${C}══════════════════════════════════════════════════════════${N}"
echo ""

# ============================================================
#  1. Обновление системы (интерактивно)
# ============================================================
update_system() {
    step "Обновление системы"
    echo ""
    echo -e "  ${D}apt может задать вопросы (конфиги, раскладка) — отвечайте осознанно.${N}"
    echo ""

    if [[ "$OS_FAMILY" == "debian" ]]; then
        if apt update -y && apt upgrade -y; then
            run_quiet "очистка пакетов" bash -c \
                "apt autoremove -y && apt autoclean -y"
            ok
            report "Система обновлена и очищена"
        else
            fail
            report "ОШИБКА: не удалось обновить систему"
        fi
    else
        if dnf update -y --security; then
            run_quiet "очистка пакетов" bash -c \
                "dnf autoremove -y && dnf clean all"
            ok
            report "Система обновлена и очищена"
        else
            fail
            report "ОШИБКА: не удалось обновить систему"
        fi
    fi
}

# ============================================================
#  2. Установка базовых утилит
# ============================================================
install_utils() {
    step "Установка базовых утилит"

    local packages=()
    local selected=()

    [[ "$INSTALL_BASE" =~ ^[Yy]$ ]]       && { packages+=(curl wget git ca-certificates gnupg lsb-release); selected+=("базовые"); }
    [[ "$INSTALL_EDITORS" =~ ^[Yy]$ ]]    && { packages+=(vim nano); selected+=("редакторы"); }
    [[ "$INSTALL_MONITORING" =~ ^[Yy]$ ]] && { packages+=(htop iotop iftop); selected+=("мониторинг"); }
    [[ "$INSTALL_ARCHIVE" =~ ^[Yy]$ ]]    && { packages+=(unzip zip rsync tar); selected+=("архивы"); }
    if [[ "$INSTALL_NET" =~ ^[Yy]$ ]]; then
        if [[ "$OS_FAMILY" == "debian" ]]; then
            packages+=(net-tools dnsutils traceroute mtr-tiny telnet)
        else
            packages+=(net-tools bind-utils traceroute mtr telnet)
        fi
        selected+=("сеть")
    fi

    if [[ ${#packages[@]} -eq 0 ]]; then
        skip
        report "Базовые утилиты: ничего не выбрано"
        return
    fi

    local rc=0
    if [[ "$OS_FAMILY" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive run_quiet "установка утилит" \
            apt install -y "${packages[@]}" || rc=$?
    else
        run_quiet "установка утилит" dnf install -y "${packages[@]}" || rc=$?
    fi

    if [[ $rc -eq 0 ]]; then
        ok
        report "Установлены утилиты (${selected[*]})"
    else
        fail
        report "ОШИБКА: не удалось установить утилиты"
    fi
}

# ============================================================
#  3. SSH
# ============================================================
setup_ssh() {
    step "Настройка SSH"

    local KEY_PATH="/root/.ssh/id_ed25519"
    local PUB_KEY_PATH="${KEY_PATH}.pub"
    local AUTH_KEYS="/root/.ssh/authorized_keys"
    local SSHD_CONFIG="/etc/ssh/sshd_config"
    local DROPIN_DIR="/etc/ssh/sshd_config.d"
    local HARDENING_DROPIN="${DROPIN_DIR}/99-hardening.conf"
    local KEY_CREATED="no"

    {
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh

        if [[ -s "$KEY_PATH" && -s "$PUB_KEY_PATH" ]]; then
            echo "[ssh] Ключ уже существует: $KEY_PATH"
        else
            echo "[ssh] Генерирую новый ed25519 ключ..."
            rm -f "$KEY_PATH" "$PUB_KEY_PATH"
            ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "root@$(hostname)"
            chmod 600 "$KEY_PATH"
            chmod 644 "$PUB_KEY_PATH"
            KEY_CREATED="yes"
        fi

        if [[ -f "$PUB_KEY_PATH" ]]; then
            if [[ -s "$AUTH_KEYS" ]]; then
                cp "$AUTH_KEYS" "${AUTH_KEYS}.bak.$(date +%s)"
                echo "[ssh] Существующие ключи в authorized_keys:"
                awk '{print "  - "$NF}' "$AUTH_KEYS"
            fi
            touch "$AUTH_KEYS"
            chmod 600 "$AUTH_KEYS"

            local key_body
            key_body=$(awk '{print $1" "$2}' "$PUB_KEY_PATH")
            if awk -v kb="$key_body" '{if ($1" "$2 == kb) found=1} END{exit !found}' "$AUTH_KEYS"; then
                echo "[ssh] Наш ключ уже в authorized_keys."
            else
                cat "$PUB_KEY_PATH" >> "$AUTH_KEYS"
                echo "[ssh] Наш ключ добавлен в authorized_keys (чужие сохранены)."
            fi
        fi

        cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak.$(date +%s)"

        if [[ "$SSH_PORT" != "22" ]]; then
            sed -i "s/^#\?Port .*/Port ${SSH_PORT}/" "$SSHD_CONFIG"
        fi
        sed -i 's/^#\?X11Forwarding .*/X11Forwarding no/' "$SSHD_CONFIG"
        sed -i 's/^#\?MaxAuthTries .*/MaxAuthTries 3/' "$SSHD_CONFIG"
        sed -i 's/^#\?ClientAliveInterval .*/ClientAliveInterval 300/' "$SSHD_CONFIG"
        sed -i 's/^#\?ClientAliveCountMax .*/ClientAliveCountMax 2/' "$SSHD_CONFIG"
        sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' "$SSHD_CONFIG"
        sed -i 's/^#\?UsePAM .*/UsePAM yes/' "$SSHD_CONFIG"
        grep -q '^UsePAM' "$SSHD_CONFIG" || echo 'UsePAM yes' >> "$SSHD_CONFIG"
        sed -i 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
        grep -q '^PubkeyAuthentication' "$SSHD_CONFIG" || echo 'PubkeyAuthentication yes' >> "$SSHD_CONFIG"
        grep -qi '^AuthorizedKeysFile' "$SSHD_CONFIG" || echo 'AuthorizedKeysFile .ssh/authorized_keys' >> "$SSHD_CONFIG"

        mkdir -p "$DROPIN_DIR"
        cat > "$HARDENING_DROPIN" <<EOF
# Создан скриптом настройки сервера — перекрывает 50-cloud-init.conf
PubkeyAuthentication yes
UsePAM yes
PermitRootLogin prohibit-password
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
PasswordAuthentication $( [[ "$DISABLE_PASS" =~ ^[Yy]$ ]] && echo no || echo yes )
KbdInteractiveAuthentication $( [[ "$DISABLE_PASS" =~ ^[Yy]$ ]] && echo no || echo yes )
EOF
        chmod 600 "$HARDENING_DROPIN"
    } >> "$LOG_FILE" 2>&1

    if ! sshd -t >> "$LOG_FILE" 2>&1; then
        fail
        cp "${SSHD_CONFIG}.bak."* "$SSHD_CONFIG" 2>/dev/null || true
        rm -f "$HARDENING_DROPIN"
        restart_ssh
        report "ОШИБКА: sshd_config восстановлен из бэкапа"
        return
    fi

    restart_ssh
    ok
    report "SSH: порт $SSH_PORT, UsePAM=yes, Pubkey=yes, X11 off"

    if [[ "$KEY_CREATED" == "yes" ]]; then
        echo "" >&3
        echo -e "${C}=================== ВАШ ПРИВАТНЫЙ SSH-КЛЮЧ ===================${N}" >&3
        echo -e "${Y}Скопируйте содержимое в файл на клиенте.${N}" >&3
        echo "" >&3
        cat "$KEY_PATH" >&3
        echo "" >&3
        echo -e "${C}==============================================================${N}" >&3
        echo -e "${Y}Файл на сервере:${N} $KEY_PATH" >&3
        echo -e "${Y}Скопировать:${N} scp root@<IP>:$KEY_PATH ~/.ssh/id_ed25519" >&3
        echo "" >&3
        report "Приватный ключ выведен на экран (сохраните!)"
    fi

    if [[ "$DISABLE_PASS" =~ ^[Yy]$ ]]; then
        if [[ "$CHECK_KEY_OK" =~ ^[Yy][Ee][Ss]$ ]]; then
            report "Вход по паролю отключён (пользователь подтвердил проверку ключа)"
        else
            {
                sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' "$HARDENING_DROPIN"
                sed -i 's/^KbdInteractiveAuthentication .*/KbdInteractiveAuthentication yes/' "$HARDENING_DROPIN"
                sshd -t && restart_ssh
            } >> "$LOG_FILE" 2>&1
            echo "" >&3
            echo -e "${Y}[!] Вы не подтвердили проверку входа по ключу. Пароль оставлен ВКЛЮЧЁННЫМ.${N}" >&3
            echo -e "${Y}    После проверки отключите вручную:${N}" >&3
            echo -e "      sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' $HARDENING_DROPIN" >&3
            echo -e "      systemctl restart $SSH_RESTART_UNIT" >&3
            echo "" >&3
            report "Пароль НЕ отключён (пользователь не подтвердил проверку ключа)"
        fi
    else
        report "Вход по паролю оставлен включённым (по выбору)"
    fi
}

# ============================================================
#  4. Fail2ban
# ============================================================
setup_fail2ban() {
    step "Fail2ban"

    if [[ ! "$WANT_F2B" =~ ^[Yy]$ ]]; then
        skip
        report "Fail2ban: не устанавливался (по выбору)"
        return
    fi

    local rc=0
    if [[ "$OS_FAMILY" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive run_quiet "установка fail2ban" \
            apt install -y fail2ban || rc=$?
    else
        run_quiet "установка fail2ban" dnf install -y fail2ban || rc=$?
    fi

    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = $SSH_PORT
filter   = sshd
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = $F2B_MAXRETRY
bantime  = $F2B_BANTIME
findtime = $F2B_FINDTIME
EOF

    systemctl enable fail2ban >> "$LOG_FILE" 2>&1 || true
    if run_quiet "запуск fail2ban" systemctl restart fail2ban; then
        ok
        report "Fail2ban: ban=${F2B_BANTIME}с, maxretry=$F2B_MAXRETRY"
        FAIL2BAN_ENABLED="yes"
    else
        fail
        report "ОШИБКА: fail2ban не запустился"
    fi
}

# ============================================================
#  5. Firewall
# ============================================================
setup_firewall() {
    step "Firewall"

    if [[ ! "$WANT_FW" =~ ^[Yy]$ ]]; then
        skip
        report "Firewall: не настраивался (по выбору)"
        return
    fi

    if [[ "$OS_FAMILY" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive run_quiet "установка ufw" \
            apt install -y ufw || true
    else
        run_quiet "установка firewalld" dnf install -y firewalld || true
    fi

    # --- Разбор портов ---
    local allowed_ports=()
    if [[ -z "${PORTS_INPUT:-}" ]]; then
        # Дефолт: если SSH-порт = 22 → 22 80 443; иначе → SSH_PORT 80 443
        if [[ "$SSH_PORT" == "22" ]]; then
            allowed_ports=(22 80 443)
        else
            allowed_ports=("$SSH_PORT" 80 443)
        fi
    else
        PORTS_INPUT="${PORTS_INPUT//,/ }"
        read -ra allowed_ports <<< "$PORTS_INPUT"
    fi

    # --- Если SSH-порт ≠ 22 и пользователь не указал 22 явно, убираем 22 из списка ---
    if [[ "$SSH_PORT" != "22" ]]; then
        local user_specified_22="no"
        if [[ -n "${PORTS_INPUT:-}" ]]; then
            for p in "${allowed_ports[@]}"; do
                [[ "$p" == "22" ]] && user_specified_22="yes"
            done
        fi
        if [[ "$user_specified_22" == "no" ]]; then
            local filtered=()
            for p in "${allowed_ports[@]}"; do
                [[ "$p" != "22" ]] && filtered+=("$p")
            done
            allowed_ports=("${filtered[@]}")
        fi
    fi

    # --- Принудительно добавляем фактический SSH-порт ---
    local ssh_present="no"
    for p in "${allowed_ports[@]}"; do
        [[ "$p" == "$SSH_PORT" ]] && ssh_present="yes"
    done
    if [[ "$ssh_present" == "no" ]]; then
        warn "SSH-порт $SSH_PORT отсутствует в списке — добавляю принудительно, чтобы не потерять доступ."
        allowed_ports+=("$SSH_PORT")
    fi

    # --- Валидация ---
    local valid_ports=()
    for p in "${allowed_ports[@]}"; do
        if [[ "$p" =~ ^[0-9]+$ ]] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]; then
            valid_ports+=("$p")
        fi
    done
    allowed_ports=("${valid_ports[@]}")

    if [[ "$OS_FAMILY" == "debian" ]]; then
        run_quiet "настройка ufw" bash -c "
            ufw --force reset
            ufw default deny incoming
            ufw default allow outgoing
            $(for p in "${allowed_ports[@]}"; do
                comment="port $p"
                [[ "$p" == "$SSH_PORT" ]] && comment="SSH"
                [[ "$p" == "80" ]]  && comment="HTTP"
                [[ "$p" == "443" ]] && comment="HTTPS"
                echo "ufw allow $p/tcp comment '$comment'"
            done)
            ufw --force enable
        "
        ok
        report "UFW: разрешены TCP ${allowed_ports[*]}"
        FIREWALL_ENABLED="yes"
    else
        run_quiet "настройка firewalld" bash -c "
            systemctl enable --now firewalld
            for p in \$(firewall-cmd --permanent --list-ports 2>/dev/null); do
                firewall-cmd --permanent --remove-port=\"\$p\" 2>/dev/null || true
            done
            $(for p in "${allowed_ports[@]}"; do echo "firewall-cmd --permanent --add-port=$p/tcp"; done)
            firewall-cmd --reload
        "
        ok
        report "Firewalld: разрешены TCP ${allowed_ports[*]}"
        FIREWALL_ENABLED="yes"
    fi
}

# ============================================================
#  6. Автообновления
# ============================================================
setup_auto_updates() {
    step "Автоматические обновления"

    if [[ ! "$WANT_AUTO" =~ ^[Yy]$ ]]; then
        skip
        report "Автообновления: не настроены (по выбору)"
        return
    fi

    if [[ "$OS_FAMILY" == "debian" ]]; then
        DEBIAN_FRONTEND=noninteractive run_quiet "настройка unattended-upgrades" \
            apt install -y unattended-upgrades apt-listchanges || true

        cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
        run_quiet "включение unattended-upgrades" \
            systemctl enable unattended-upgrades
        ok
        report "Автообновления: unattended-upgrades включён"
    else
        run_quiet "настройка dnf-automatic" dnf install -y dnf-automatic || true
        sed -i 's/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
        run_quiet "включение dnf-automatic" \
            systemctl enable --now dnf-automatic.timer
        ok
        report "Автообновления: dnf-automatic включён"
    fi
}

# ============================================================
#  7. Timezone
# ============================================================
setup_timezone() {
    step "Часовой пояс"
    if run_quiet "установка timezone" bash -c \
        "timedatectl set-timezone '$TZ' && timedatectl set-ntp true"; then
        ok
        report "Часовой пояс: $TZ, NTP включён"
    else
        fail
        report "ОШИБКА: не удалось установить часовой пояс"
    fi
}

# ============================================================
#  8. Swap
# ============================================================
setup_swap() {
    step "Swap"

    if swapon --show | grep -q .; then
        skip
        report "Swap уже активен"
        return
    fi

    if [[ ! "$WANT_SWAP" =~ ^[Yy]$ ]]; then
        skip
        report "Swap не создавался (по выбору)"
        return
    fi

    run_quiet "создание swap 1GB" bash -c "
        fallocate -l 1G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        sysctl vm.swappiness=10
        grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
    "
    ok
    report "Создан swap 1GB, vm.swappiness=10"
}

# ============================================================
#  9. Sysctl
# ============================================================
setup_sysctl() {
    step "Sysctl (сеть/TCP)"

    if [[ ! "$WANT_SYSCTL" =~ ^[Yy]$ ]]; then
        skip
        report "sysctl: не настроен (по выбору)"
        return
    fi

    cat > /etc/sysctl.d/99-hardening.conf <<'EOF'
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 65536 6291456
net.core.rmem_max = 6291456
net.core.wmem_max = 6291456
net.ipv4.tcp_rfc1337 = 1
EOF

    if run_quiet "применение sysctl" sysctl -p /etc/sysctl.d/99-hardening.conf; then
        ok
        report "sysctl: сеть/TCP защита применена"
    else
        fail
        report "ОШИБКА: sysctl не применились"
    fi
}

# ============================================================
#  10. Лимиты
# ============================================================
setup_limits() {
    step "Системные лимиты"

    if [[ ! "$WANT_LIMITS" =~ ^[Yy]$ ]]; then
        skip
        report "Лимиты: не настроены (по выбору)"
        return
    fi

    cat > /etc/security/limits.d/99-hardening.conf <<EOF
* soft nofile $LIMITS_NOFILE
* hard nofile $LIMITS_NOFILE
* soft nproc $LIMITS_NPROC
* hard nproc $LIMITS_NPROC
root soft nofile $LIMITS_NOFILE
root hard nofile $LIMITS_NOFILE
root soft nproc $LIMITS_NPROC
root hard nproc $LIMITS_NPROC
EOF

    if [[ -d /etc/systemd/system.conf.d ]]; then
        cat > /etc/systemd/system.conf.d/99-limits.conf <<EOF
[Manager]
DefaultLimitNOFILE=$LIMITS_NOFILE
DefaultLimitNPROC=$LIMITS_NPROC
EOF
        run_quiet "применение лимитов systemd" systemctl daemon-reexec || true
    fi

    ok
    report "Лимиты: nofile=$LIMITS_NOFILE, nproc=$LIMITS_NPROC"
}

# ============================================================
#  11. ICMP
# ============================================================
disable_icmp() {
    step "ICMP (ping)"

    if [[ "$WANT_NOICMP" =~ ^[Yy]$ ]]; then
        cat > /etc/sysctl.d/99-disable-icmp.conf <<'EOF'
net.ipv4.icmp_echo_ignore_all = 1
EOF
        run_quiet "применение ICMP" sysctl --system
        ICMP_DISABLED="yes"
        ok
        report "ICMP-пинг отключён"
    else
        cat > /etc/sysctl.d/99-disable-icmp.conf <<'EOF'
net.ipv4.icmp_echo_ignore_all = 0
EOF
        run_quiet "применение ICMP" sysctl --system
        ICMP_DISABLED="no"
        skip
        report "ICMP-пинг оставлен разрешённым"
    fi
}

# ============================================================
#  12. Очистка логов и мусора
# ============================================================
cleanup_logs() {
    step "Очистка логов и мусора"

    run_quiet "очистка логов и мусора" bash -c "
        if [[ -f /etc/systemd/journald.conf ]]; then
            grep -q '^#\?SystemMaxUse=' /etc/systemd/journald.conf \
                && sed -i 's/^#\?SystemMaxUse=.*/SystemMaxUse=500M/' /etc/systemd/journald.conf \
                || echo 'SystemMaxUse=500M' >> /etc/systemd/journald.conf
            grep -q '^#\?MaxRetentionSec=' /etc/systemd/journald.conf \
                && sed -i 's/^#\?MaxRetentionSec=.*/MaxRetentionSec=${LOG_RETENTION_DAYS}d/' /etc/systemd/journald.conf \
                || echo 'MaxRetentionSec=${LOG_RETENTION_DAYS}d' >> /etc/systemd/journald.conf
            systemctl restart systemd-journald 2>/dev/null || true
            journalctl --vacuum-time='${LOG_RETENTION_DAYS}d' >/dev/null 2>&1 || true
        fi

        if [[ -d /etc/logrotate.d ]]; then
            for conf in /etc/logrotate.d/*; do
                [[ -f \"\$conf\" ]] || continue
                grep -q '^\s*rotate ' \"\$conf\" && sed -i 's/^\s*rotate .*/    rotate ${LOG_RETENTION_DAYS}/' \"\$conf\"
                grep -q '^\s*maxage ' \"\$conf\" && sed -i 's/^\s*maxage .*/    maxage ${LOG_RETENTION_DAYS}/' \"\$conf\"
            done
        fi

        find /var/log -type f \( -name '*.log' -o -name '*.gz' -o -name '*.old' \) -mtime +'${LOG_RETENTION_DAYS}' -delete 2>/dev/null || true
        find /tmp     -type f -mtime +'${LOG_RETENTION_DAYS}' -delete 2>/dev/null || true
        find /var/tmp -type f -mtime +'${LOG_RETENTION_DAYS}' -delete 2>/dev/null || true

        if [[ '$OS_FAMILY' == 'debian' ]]; then
            apt autoremove -y 2>/dev/null || true
            apt autoclean -y  2>/dev/null || true
            find /var/cache/apt/archives -type f -name '*.deb' -mtime +'${LOG_RETENTION_DAYS}' -delete 2>/dev/null || true
        else
            dnf autoremove -y 2>/dev/null || true
            dnf clean all     2>/dev/null || true
            find /var/cache/dnf -type f -mtime +'${LOG_RETENTION_DAYS}' -delete 2>/dev/null || true
        fi

        if [[ '$OS_FAMILY' == 'debian' ]]; then
            current_kernel=\$(uname -r)
            installed_kernels=\$(dpkg --list 'linux-image-*' 2>/dev/null | awk '/^ii/{print \$2}' | grep -v \"\$current_kernel\" | sort -V || true)
            kernels_to_remove=()
            count=0
            while IFS= read -r k; do
                [[ -z \"\$k\" ]] && continue
                count=\$((count+1))
                [[ \$count -gt 1 ]] && kernels_to_remove+=(\"\$k\")
            done <<< \"\$installed_kernels\"
            if [[ \${#kernels_to_remove[@]} -gt 0 ]]; then
                DEBIAN_FRONTEND=noninteractive apt purge -y \"\${kernels_to_remove[@]}\" 2>/dev/null || true
            fi
        fi
    "

    ok
    report "Очистка: логи/мусор старше ${LOG_RETENTION_DAYS}д, кэш, старые ядра"
}

# ============================================================
#  13. Службы и IPv6
# ============================================================
disable_services() {
    step "Отключение служб и IPv6"

    local disabled_list=()
    local skipped_list=()
    local notfound_list=()

    declare -A SVC_PLAN=(
        [bluetooth]="$WANT_NO_BLUETOOTH"
        [cups]="$WANT_NO_CUPS"
        [avahi-daemon]="$WANT_NO_AVAHI"
        [ModemManager]="$WANT_NO_MODEM"
    )

    for svc in bluetooth cups avahi-daemon ModemManager; do
        local flag="${SVC_PLAN[$svc]}"
        local unit="${svc}.service"

        if ! systemctl list-unit-files | grep -q "^${unit}"; then
            notfound_list+=("$svc")
            continue
        fi

        if [[ "$flag" =~ ^[Yy]$ ]]; then
            run_quiet "отключение $svc" bash -c "
                systemctl stop '$svc' 2>/dev/null || true
                systemctl disable '$svc' 2>/dev/null || true
                systemctl mask '$svc' 2>/dev/null || true
            " || true
            disabled_list+=("$svc")
        else
            skipped_list+=("$svc")
        fi
    done

    local ipv6_status="оставлен"
    if [[ "$WANT_NOIPV6" =~ ^[Yy]$ ]]; then
        cat > /etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
        run_quiet "применение IPv6" sysctl --system
        ipv6_status="отключён"
    else
        cat > /etc/sysctl.d/99-disable-ipv6.conf <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv6.conf.default.disable_ipv6 = 0
net.ipv6.conf.lo.disable_ipv6 = 0
EOF
        run_quiet "применение IPv6" sysctl --system
    fi

    ok

    local report_str=""
    [[ ${#disabled_list[@]} -gt 0 ]] && report_str+="отключены: ${disabled_list[*]}; "
    [[ ${#skipped_list[@]} -gt 0 ]]  && report_str+="оставлены: ${skipped_list[*]}; "
    [[ ${#notfound_list[@]} -gt 0 ]] && report_str+="не найдены: ${notfound_list[*]}; "
    report_str+="IPv6 $ipv6_status"
    report "Службы: $report_str"
}

# ============================================================
#  ИТОГОВЫЙ ОТЧЁТ
# ============================================================
print_summary() {
    echo ""
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${C}║                    ИТОГИ НАСТРОЙКИ                       ║${N}"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${N}"
    echo ""
    echo -e "${B}Выполненные действия:${N}"
    local i=1
    for item in "${REPORT[@]}"; do
        echo -e "  ${G}${i}.${N} $item"
        ((i++))
    done
    echo ""
    echo -e "${C}──────────────────────────────────────────────────────────${N}"
    echo -e "${B}Статус подсистем:${N}"
    echo ""

    if [[ "$FIREWALL_ENABLED" == "yes" ]]; then
        if [[ "$OS_FAMILY" == "debian" ]]; then
            echo -e "  Firewall:  ${G}$(ufw status | head -1)${N}"
        else
            echo -e "  Firewall:  ${G}$(systemctl is-active firewalld)${N}"
        fi
    else
        echo -e "  Firewall:  ${D}не настраивался${N}"
    fi

    if [[ "$FAIL2BAN_ENABLED" == "yes" ]]; then
        echo -e "  Fail2ban:  ${G}$(systemctl is-active fail2ban)${N}"
    else
        echo -e "  Fail2ban:  ${D}не устанавливался${N}"
    fi

    if swapon --show | grep -q .; then
        echo -e "  Swap:      ${G}$(swapon --show --noheadings | awk '{print $1, $3}')${N}"
    else
        echo -e "  Swap:      ${D}не активен${N}"
    fi

    echo -e "  Timezone:  ${G}$(timedatectl show --property=Timezone --value)${N}"
    echo -e "  NTP:       $(timedatectl show --property=NTP --value)"

    local icmp_status
    icmp_status=$(sysctl -n net.ipv4.icmp_echo_ignore_all 2>/dev/null || echo "?")
    if [[ "$icmp_status" == "1" ]]; then
        echo -e "  ICMP:      ${R}отключён${N}"
    else
        echo -e "  ICMP:      ${G}разрешён${N}"
    fi

    echo ""
    echo -e "  UsePAM:                $(sshd -T 2>/dev/null | awk '/^usepam /{print $2}')"
    echo -e "  PasswordAuthentication: $(sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')"
    echo -e "  PubkeyAuthentication:   $(sshd -T 2>/dev/null | awk '/^pubkeyauthentication /{print $2}')"
    echo -e "  PermitRootLogin:        $(sshd -T 2>/dev/null | awk '/^permitrootlogin /{print $2}')"

    if [[ -f /root/.ssh/authorized_keys ]]; then
        echo -e "  Ключей в authorized_keys: $(grep -c . /root/.ssh/authorized_keys 2>/dev/null || echo 0)"
    fi

    echo -e "  Свободно на /: $(df -h / | awk 'NR==2{print $4" ("$5" занято)"}')"

    echo ""
    echo -e "${C}──────────────────────────────────────────────────────────${N}"
    echo -e "  ${D}Полный лог:${N} $LOG_FILE"
    echo -e "${C}──────────────────────────────────────────────────────────${N}"
    echo ""

    echo -e "${Y}${B}ВАЖНО:${N}"
    echo -e "${Y}  1. Проверьте вход по SSH в НОВОЙ сессии, не закрывая текущую!${N}"
    if [[ "$SSH_PORT" != "22" ]]; then
        echo -e "${Y}     ssh -p $SSH_PORT root@<IP>${N}"
    fi
    echo -e "${Y}  2. Сохраните приватный ключ, если он был выведен выше!${N}"
    if [[ "$DISABLE_PASS" =~ ^[Yy]$ ]] && [[ ! "$CHECK_KEY_OK" =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${Y}  3. Пароль НЕ отключён (вы не подтвердили проверку ключа).${N}"
        echo -e "${Y}     Отключить вручную после проверки:${N}"
        echo -e "${Y}       sed -i 's/^PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config.d/99-hardening.conf${N}"
        echo -e "${Y}       systemctl restart $SSH_RESTART_UNIT${N}"
    fi
    if [[ "$ICMP_DISABLED" == "yes" ]]; then
        echo -e "${Y}  4. ICMP отключён — проверьте мониторинг провайдера.${N}"
    fi
    echo ""
}

# ============================================================
#  MAIN
# ============================================================
main() {
    echo ""
    echo -e "${C}╔══════════════════════════════════════════════════════════╗${N}"
    echo -e "${C}║          Настройка и защита Linux-сервера                ║${N}"
    echo -e "${C}╚══════════════════════════════════════════════════════════╝${N}"
    echo ""

    detect_ssh_unit
    configure_debconf

    update_system
    install_utils
    setup_ssh
    setup_fail2ban
    setup_firewall
    setup_auto_updates
    setup_timezone
    setup_swap
    setup_sysctl
    setup_limits
    disable_icmp
    cleanup_logs
    disable_services

    print_summary
}

main
