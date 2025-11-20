#!/bin/bash

# ========== Logging Function ==========
log_message() {
    local type="$1"
    local message="$2"
    local term_width
    term_width=$(tput cols)
    local stars_count=$((term_width - ${#message} - 10))
    local stars
    stars=$(printf '*%.0s' $(seq 1 "$stars_count"))

    case "$type" in
        task)
            echo -e "\e[1;37m\nTASK [ $message ] $stars\e[0m"
            ;;
        ok)
            echo -e "\e[1;32mok: [localhost] => $message\e[0m"
            ;;
        changed)
            echo -e "\e[1;33mchanged: [localhost] => $message\e[0m"
            ;;
        info)
            echo -e "\e[1;36mINFO: $message\e[0m"
            ;;
        *)
            echo -e "\e[1;31mUnknown log type: $type\e[0m"
            ;;
    esac
}

# ========== User Creation ==========
USER="guac"
PASSWORD='$6$McanchlqUns4b2EO$GLzhdpA2jGMZ1mKFISRnevsnG8Fuj3kbFdGAkGNcS27yOPku8eLi7aLknztGvsa4cErajmv0l6wc5fjr7HQIk0'

log_message "task" "Create user '$USER'"
if id "$USER" &>/dev/null; then
    log_message "ok" "User '$USER' already exists"
else
    useradd -m -s /usr/bin/bash -U --groups adm,dialout,cdrom,floppy,sudo,audio,dip,video,plugdev,netdev --password "$PASSWORD" "$USER"
    log_message "changed" "User '$USER' created"
fi

# ========== Sudoers Configuration ==========
SUDOERS_LINE="$USER ALL=(ALL) NOPASSWD: ALL"

log_message "task" "Add sudoers entry for '$USER'"
if grep -qF "$SUDOERS_LINE" /etc/sudoers; then
    log_message "ok" "Sudoers entry for '$USER' already exists"
else
    echo -e "\n# Allow $USER to execute any sudo command without password\n$SUDOERS_LINE" >> /etc/sudoers
    log_message "changed" "Sudoers entry added"
fi

# ========== WSL Config ==========
HOSTNAME="$1"
WSL_CONF="/etc/wsl.conf"

log_message "task" "Configure WSL settings"
cat << EOF > "$WSL_CONF"
[user]
default=$USER

[network]
hostname = $HOSTNAME

[automount]
options = "metadata"
EOF
log_message "changed" "WSL configuration written to $WSL_CONF"

# ========== Configure Passwordless Sudo for Startup Script ==========
log_message "task" "Configure passwordless sudo for Guacamole startup script"
cat > /etc/sudoers.d/guacamole-startup <<SUDOERS
$USER ALL=(ALL) NOPASSWD: /usr/local/bin/start-guacamole.sh
SUDOERS
chmod 440 /etc/sudoers.d/guacamole-startup
log_message "changed" "Passwordless sudo configured for startup script"
