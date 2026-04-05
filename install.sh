#!/bin/bash
set -euo pipefail

# ══════════════════════════════════════════════════════════
#  DigitalD.tech VPN Panel Installer — Modern UI
# ══════════════════════════════════════════════════════════

# ─── Terminal capabilities ───
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[0;37m'

# ─── Symbols ───
SYM_OK="✓"
SYM_FAIL="✗"
SYM_ARROW="›"
SYM_DOT="•"
SPINNER_FRAMES=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# ─── Install paths ───
INSTALL_DIR="/opt/vpn-panel"
DATA_DIR="$INSTALL_DIR/data"
CERTS_DIR="$INSTALL_DIR/certs"
CONFIGS_DIR="$INSTALL_DIR/configs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_RELEASE_REPO="${PUBLIC_RELEASE_REPO:-tnzil/all-in-one-vpn-panel}"
PUBLIC_RELEASE_BUNDLE="${PUBLIC_RELEASE_BUNDLE:-vpn-panel-bundle.tar.gz}"

# ─── Step tracking ───
STEP_CURRENT=0
STEP_TOTAL=15
STEP_START_TIME=0

# ─── Spinner state ───
SPINNER_PID=""

# ─── Utilities ───

_elapsed() {
    local end now diff
    now=$(date +%s%N 2>/dev/null) || now=$(($(date +%s) * 1000000000))
    diff=$(( (now - STEP_START_TIME) / 1000000 ))
    printf "%d.%ds" $((diff / 1000)) $(( (diff % 1000) / 100 ))
}

_stop_spinner() {
    if [ -n "$SPINNER_PID" ] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
}

_start_spinner() {
    local label="$1"
    local col_w=44
    local idx=0
    local padded
    padded=$(printf "%-${col_w}s" "$label")
    # Print the label line (no newline) then spin in place
    printf "  ${DIM}[%2d/%-2d]${NC}  ${WHITE}%s${NC}" "$STEP_CURRENT" "$STEP_TOTAL" "$padded"
    (
        while true; do
            printf "\r  ${DIM}[%2d/%-2d]${NC}  ${WHITE}%s${NC}  ${CYAN}%s${NC}" \
                "$STEP_CURRENT" "$STEP_TOTAL" "$padded" "${SPINNER_FRAMES[$idx]}"
            idx=$(( (idx + 1) % 10 ))
            sleep 0.08
        done
    ) &
    SPINNER_PID=$!
}

_finish_step() {
    local status="$1"   # ok | fail | skip
    local label="$2"
    local col_w=44
    local padded elapsed_str
    padded=$(printf "%-${col_w}s" "$label")
    elapsed_str=$(_elapsed)

    _stop_spinner

    case "$status" in
        ok)
            printf "\r  ${DIM}[%2d/%-2d]${NC}  ${WHITE}%s${NC}  ${GREEN}%s${NC}  ${DIM}%s${NC}\n" \
                "$STEP_CURRENT" "$STEP_TOTAL" "$padded" "$SYM_OK" "$elapsed_str"
            ;;
        skip)
            printf "\r  ${DIM}[%2d/%-2d]${NC}  ${WHITE}%s${NC}  ${YELLOW}─${NC}  ${DIM}skipped${NC}\n" \
                "$STEP_CURRENT" "$STEP_TOTAL" "$padded"
            ;;
        fail)
            printf "\r  ${DIM}[%2d/%-2d]${NC}  ${WHITE}%s${NC}  ${RED}%s${NC}  ${DIM}%s${NC}\n" \
                "$STEP_CURRENT" "$STEP_TOTAL" "$padded" "$SYM_FAIL" "$elapsed_str"
            ;;
    esac
}

# Run a task: show spinner, execute, show result
# Usage: task "Label" command [args...]
task() {
    local label="$1"
    shift
    STEP_CURRENT=$(( STEP_CURRENT + 1 ))
    STEP_START_TIME=$(date +%s%N 2>/dev/null) || STEP_START_TIME=$(($(date +%s) * 1000000000))

    _start_spinner "$label"

    local log_file
    log_file=$(mktemp /tmp/vpn-install-XXXXXX.log)

    if "$@" >"$log_file" 2>&1; then
        _finish_step ok "$label"
        rm -f "$log_file"
    else
        local exit_code=$?
        _finish_step fail "$label"
        echo ""
        echo -e "  ${RED}Error output:${NC}"
        tail -20 "$log_file" | sed 's/^/    /'
        rm -f "$log_file"
        echo ""
        exit "$exit_code"
    fi
}

# task_skip — mark a step as skipped without running anything
task_skip() {
    local label="$1"
    STEP_CURRENT=$(( STEP_CURRENT + 1 ))
    STEP_START_TIME=$(date +%s%N 2>/dev/null) || STEP_START_TIME=$(($(date +%s) * 1000000000))
    SPINNER_PID=""
    _finish_step skip "$label"
}

warn() { echo -e "  ${YELLOW}${SYM_DOT}${NC}  ${YELLOW}$*${NC}"; }
die()  {
    _stop_spinner
    echo ""
    echo -e "  ${RED}${SYM_FAIL}  $*${NC}"
    echo ""
    exit 1
}

# ══════════════════════════════════════════════════════════
#  Header
# ══════════════════════════════════════════════════════════

echo ""
echo -e "  ${BOLD}${BLUE}┌──────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}${BLUE}│${NC}  ${BOLD}${WHITE}🛡  DigitalD.tech VPN Panel${NC}  ${DIM}│  One-command installer${NC}          ${BOLD}${BLUE}│${NC}"
echo -e "  ${BOLD}${BLUE}└──────────────────────────────────────────────┘${NC}"
echo ""

# ─── Pre-flight checks (no spinner — fast/instant) ───
[ "$(id -u)" -ne 0 ] && die "Must be run as root"

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    [[ "$ID" == "ubuntu" || "$ID" == "debian" ]] || warn "Untested OS: $ID $VERSION_ID — continuing"
else
    warn "Cannot detect OS — continuing"
fi

# Detect server IP
SERVER_IP="${SERVER_IP:-}"
if [ -z "$SERVER_IP" ]; then
    SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null || \
                curl -4 -s --max-time 5 icanhazip.com 2>/dev/null || \
                hostname -I 2>/dev/null | awk '{print $1}')
fi
[ -z "$SERVER_IP" ] && die "Could not detect server IP. Set SERVER_IP env var and retry."
PUBLIC_HOST="${PUBLIC_HOST:-$SERVER_IP}"

echo -e "  ${DIM}Server IP detected:${NC}  ${CYAN}${SERVER_IP}${NC}"
echo -e "  ${DIM}Public endpoint:${NC}   ${CYAN}${PUBLIC_HOST}${NC}"
echo ""

# ══════════════════════════════════════════════════════════
#  Step 1 — Docker
# ══════════════════════════════════════════════════════════

_install_docker() {
    if command -v docker &>/dev/null; then
        return 0
    fi
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable --now docker
}

if command -v docker &>/dev/null; then
    task_skip "Docker  (already installed)"
else
    task "Installing Docker" _install_docker
fi

# ══════════════════════════════════════════════════════════
#  Step 2 — System dependencies
# ══════════════════════════════════════════════════════════

_install_deps() {
    apt-get install -y -qq openssl wireguard-tools openvpn python3-bcrypt certbot 2>/dev/null || true
    # Ensure TUN device exists
    if [ ! -e /dev/net/tun ]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200
        chmod 600 /dev/net/tun
    fi
}

task "Installing system dependencies" _install_deps

# ══════════════════════════════════════════════════════════
#  Step 3 — Directories
# ══════════════════════════════════════════════════════════

_create_dirs() {
    mkdir -p "$DATA_DIR" "$CERTS_DIR"
    mkdir -p \
        "$CONFIGS_DIR/haproxy" \
        "$CONFIGS_DIR/nginx" \
        "$CONFIGS_DIR/openvpn" \
        "$CONFIGS_DIR/wireguard" \
        "$CONFIGS_DIR/xray" \
        "$CONFIGS_DIR/ikev2" \
        "$CONFIGS_DIR/openconnect" \
        "$CONFIGS_DIR/amneziawg"
    mkdir -p "$DATA_DIR/openvpn" "$DATA_DIR/openconnect"
}

task "Creating directory structure" _create_dirs

# ══════════════════════════════════════════════════════════
#  Step 3b — Host sysctls
# ══════════════════════════════════════════════════════════

_configure_host_sysctls() {
    cat > /etc/sysctl.d/99-vpn-panel.conf <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.src_valid_mark = 1
EOF
    sysctl --system >/dev/null
}

task "Configuring host sysctls" _configure_host_sysctls

# ══════════════════════════════════════════════════════════
#  Step 3c — Host NAT
# ══════════════════════════════════════════════════════════

_configure_host_nat() {
    local ext_if
    ext_if=$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i+1); exit}}')
    [ -n "$ext_if" ] || ext_if="eth0"

    for subnet in 10.8.0.0/24 10.9.0.0/24 10.10.10.0/24 10.20.20.0/24 10.66.66.0/24 10.66.67.0/24; do
        iptables -t nat -C POSTROUTING -s "$subnet" -o "$ext_if" -j MASQUERADE 2>/dev/null || \
            iptables -t nat -A POSTROUTING -s "$subnet" -o "$ext_if" -j MASQUERADE
    done
}

task "Configuring host NAT" _configure_host_nat

# ══════════════════════════════════════════════════════════
#  Step 3d — Host forwarding
# ══════════════════════════════════════════════════════════

_configure_host_forwarding() {
    for subnet in 10.8.0.0/24 10.9.0.0/24 10.10.10.0/24 10.20.20.0/24 10.66.66.0/24 10.66.67.0/24; do
        iptables -C FORWARD -s "$subnet" -j ACCEPT 2>/dev/null || \
            iptables -A FORWARD -s "$subnet" -j ACCEPT
        iptables -C FORWARD -d "$subnet" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
            iptables -A FORWARD -d "$subnet" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    done

    iptables -C FORWARD -m policy --pol ipsec --dir in -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -m policy --pol ipsec --dir in -j ACCEPT
    iptables -C FORWARD -m policy --pol ipsec --dir out -j ACCEPT 2>/dev/null || \
        iptables -A FORWARD -m policy --pol ipsec --dir out -j ACCEPT
}

task "Configuring host forwarding" _configure_host_forwarding

# ══════════════════════════════════════════════════════════
#  Step 3e — Firewall persistence
# ══════════════════════════════════════════════════════════

_install_firewall_persistence() {
    cat > /usr/local/sbin/vpn-panel-fw.sh <<'EOF'
#!/bin/sh
set -eu

ext_if="$(ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i+1); exit}}')"
[ -n "$ext_if" ] || ext_if="eth0"

for subnet in 10.8.0.0/24 10.9.0.0/24 10.10.10.0/24 10.20.20.0/24 10.66.66.0/24 10.66.67.0/24; do
    iptables -w -t nat -C POSTROUTING -s "$subnet" -o "$ext_if" -j MASQUERADE 2>/dev/null || \
        iptables -w -t nat -A POSTROUTING -s "$subnet" -o "$ext_if" -j MASQUERADE
    iptables -w -C FORWARD -s "$subnet" -j ACCEPT 2>/dev/null || \
        iptables -w -A FORWARD -s "$subnet" -j ACCEPT
    iptables -w -C FORWARD -d "$subnet" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -w -A FORWARD -d "$subnet" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
done

iptables -w -C FORWARD -m policy --pol ipsec --dir in -j ACCEPT 2>/dev/null || \
    iptables -w -A FORWARD -m policy --pol ipsec --dir in -j ACCEPT
iptables -w -C FORWARD -m policy --pol ipsec --dir out -j ACCEPT 2>/dev/null || \
    iptables -w -A FORWARD -m policy --pol ipsec --dir out -j ACCEPT
EOF
    chmod 755 /usr/local/sbin/vpn-panel-fw.sh

    cat > /etc/systemd/system/vpn-panel-firewall.service <<'EOF'
[Unit]
Description=VPN Panel firewall rules
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vpn-panel-fw.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now vpn-panel-firewall.service
}

task "Installing firewall persistence" _install_firewall_persistence

# ══════════════════════════════════════════════════════════
#  Step 3f — Docker bridge networking
# ══════════════════════════════════════════════════════════

_ensure_docker_bridge_networking() {
    command -v docker >/dev/null 2>&1 || return 0

    # If Docker's bridge MASQUERADE rule is missing, bridge-networked
    # containers cannot reach DNS or package mirrors. Restart Docker so it
    # recreates its chains after any manual firewall changes.
    if ! iptables -t nat -C POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE 2>/dev/null; then
        systemctl restart docker
        sleep 3
    fi

    iptables -t nat -C POSTROUTING -s 172.17.0.0/16 ! -o docker0 -j MASQUERADE
}

task "Verifying Docker bridge networking" _ensure_docker_bridge_networking

# ══════════════════════════════════════════════════════════
#  Step 4 — Credentials
# ══════════════════════════════════════════════════════════

_gen_credentials() {
    ADMIN_USER="admin"
    ADMIN_PASS=$(openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 24)
    ADMIN_PASS_HASH=$(python3 -c \
        "import bcrypt; print(bcrypt.hashpw(b'${ADMIN_PASS}', bcrypt.gensalt()).decode())" \
        2>/dev/null || \
        htpasswd -nbBC 10 "" "$ADMIN_PASS" 2>/dev/null | tr -d ':\n')
    if [ -z "$ADMIN_PASS_HASH" ]; then
        echo "Failed to hash password — install python3-bcrypt or apache2-utils" >&2
        return 1
    fi
    SESSION_SECRET=$(openssl rand -hex 32)
    XRAY_UUID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || \
        python3 -c "import uuid; print(uuid.uuid4())")
    SS_PASSWORD=$(openssl rand -base64 16)
}

# Run synchronously so variables are exported to current shell
STEP_CURRENT=$(( STEP_CURRENT + 1 ))
STEP_START_TIME=$(date +%s%N 2>/dev/null) || STEP_START_TIME=$(($(date +%s) * 1000000000))
_start_spinner "Generating credentials"
if _gen_credentials 2>/tmp/vpn-cred.err; then
    _finish_step ok "Generating credentials"
else
    _finish_step fail "Generating credentials"
    cat /tmp/vpn-cred.err | sed 's/^/    /'
    exit 1
fi

# ══════════════════════════════════════════════════════════
#  Step 5 — Certificates
# ══════════════════════════════════════════════════════════

_gen_certs() {
    local server_san ikev2_san certbot_args le_dir

    server_san="IP:$SERVER_IP,DNS:localhost"
    ikev2_san="IP:$SERVER_IP"
    if [ "$PUBLIC_HOST" != "$SERVER_IP" ]; then
        server_san="$server_san,DNS:$PUBLIC_HOST"
        ikev2_san="$ikev2_san,DNS:$PUBLIC_HOST"
    fi

    # CA
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes \
        -keyout "$CERTS_DIR/ca.key" -out "$CERTS_DIR/ca.crt" \
        -subj "/CN=DigitalD.tech CA/O=DigitalD.tech" 2>/dev/null

    # Server cert
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -nodes -keyout "$CERTS_DIR/server.key" -out /tmp/server.csr \
        -subj "/CN=$PUBLIC_HOST/O=DigitalD.tech" 2>/dev/null
    cat > /tmp/server_ext.cnf <<EXTEOF
subjectAltName=$server_san
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EXTEOF
    openssl x509 -req -in /tmp/server.csr \
        -CA "$CERTS_DIR/ca.crt" -CAkey "$CERTS_DIR/ca.key" -CAcreateserial \
        -out "$CERTS_DIR/server.crt" -days 730 \
        -extfile /tmp/server_ext.cnf 2>/dev/null

    # IKEv2 cert
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -nodes -keyout "$CERTS_DIR/ikev2-server.key" -out /tmp/ikev2.csr \
        -subj "/CN=$PUBLIC_HOST/O=DigitalD.tech IKEv2" 2>/dev/null
    cat > /tmp/ikev2_ext.cnf <<EXTEOF
subjectAltName=$ikev2_san
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EXTEOF
    openssl x509 -req -in /tmp/ikev2.csr \
        -CA "$CERTS_DIR/ca.crt" -CAkey "$CERTS_DIR/ca.key" -CAcreateserial \
        -out "$CERTS_DIR/ikev2-server.crt" -days 730 \
        -extfile /tmp/ikev2_ext.cnf 2>/dev/null
    cp "$CERTS_DIR/ca.crt" "$CERTS_DIR/ikev2-ca.crt"
    cp "$CERTS_DIR/ca.crt" "$CERTS_DIR/ikev2-client-ca.crt"

    if [ "$PUBLIC_HOST" != "$SERVER_IP" ] && command -v certbot >/dev/null 2>&1; then
        certbot_args=(certonly --standalone --non-interactive --agree-tos --key-type rsa --rsa-key-size 2048 -d "$PUBLIC_HOST")
        if [ -n "${LETSENCRYPT_EMAIL:-}" ]; then
            certbot_args+=(--email "$LETSENCRYPT_EMAIL")
        else
            certbot_args+=(--register-unsafely-without-email)
        fi
        if certbot "${certbot_args[@]}" >/dev/null 2>&1; then
            le_dir="/etc/letsencrypt/live/$PUBLIC_HOST"
            cp "$le_dir/cert.pem" "$CERTS_DIR/ikev2-server.crt"
            cp "$le_dir/privkey.pem" "$CERTS_DIR/ikev2-server.key"
            cp "$le_dir/chain.pem" "$CERTS_DIR/ikev2-ca.crt"
            if [ -f /etc/ssl/certs/ISRG_Root_X1.pem ]; then
                cp /etc/ssl/certs/ISRG_Root_X1.pem "$CERTS_DIR/ikev2-client-ca.crt"
            else
                cp "$le_dir/chain.pem" "$CERTS_DIR/ikev2-client-ca.crt"
            fi
        fi
    fi

    # DH params (takes a moment)
    openssl dhparam -out "$CERTS_DIR/dh.pem" 2048 2>/dev/null

    # OpenVPN TLS auth key
    openvpn --genkey secret "$CERTS_DIR/ta.key" 2>/dev/null || \
        openssl rand 256 > "$CERTS_DIR/ta.key"

    chmod 600 "$CERTS_DIR"/*.key
    chmod 644 "$CERTS_DIR/ikev2-server.key"
    chmod 644 "$CERTS_DIR"/*.crt "$CERTS_DIR/dh.pem"
    rm -f /tmp/server.csr /tmp/server_ext.cnf /tmp/ikev2.csr /tmp/ikev2_ext.cnf "$CERTS_DIR/ca.srl"
}

task "Generating TLS certificates & DH params" _gen_certs

# ══════════════════════════════════════════════════════════
#  Step 5b — Let's Encrypt renewal hook
# ══════════════════════════════════════════════════════════

_install_le_renewal_hook() {
    [ "$PUBLIC_HOST" != "$SERVER_IP" ] || return 0
    command -v certbot >/dev/null 2>&1 || return 0
    [ -d "/etc/letsencrypt/live/$PUBLIC_HOST" ] || return 0

    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/vpn-panel.sh <<EOF
#!/bin/sh
set -eu

[ "\${RENEWED_LINEAGE:-}" = "/etc/letsencrypt/live/$PUBLIC_HOST" ] || exit 0

install -m 0644 "\$RENEWED_LINEAGE/cert.pem" "$CERTS_DIR/ikev2-server.crt"
install -m 0644 "\$RENEWED_LINEAGE/privkey.pem" "$CERTS_DIR/ikev2-server.key"
install -m 0644 "\$RENEWED_LINEAGE/chain.pem" "$CERTS_DIR/ikev2-ca.crt"

if [ -f /etc/ssl/certs/ISRG_Root_X1.pem ]; then
    install -m 0644 /etc/ssl/certs/ISRG_Root_X1.pem "$CERTS_DIR/ikev2-client-ca.crt"
else
    install -m 0644 "\$RENEWED_LINEAGE/chain.pem" "$CERTS_DIR/ikev2-client-ca.crt"
fi

if command -v docker >/dev/null 2>&1 && [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    docker compose -f "$INSTALL_DIR/docker-compose.yml" restart ikev2 >/dev/null 2>&1 || \
        docker restart vpn-ikev2 >/dev/null 2>&1 || true
fi
EOF
    chmod 755 /etc/letsencrypt/renewal-hooks/deploy/vpn-panel.sh
    systemctl enable --now certbot.timer >/dev/null 2>&1 || true
}

if [ "$PUBLIC_HOST" != "$SERVER_IP" ]; then
    task "Installing Let's Encrypt renewal hook" _install_le_renewal_hook
else
    task_skip "Let's Encrypt renewal hook"
fi

# ══════════════════════════════════════════════════════════
#  Step 6 — WireGuard keys + Xray paths
# ══════════════════════════════════════════════════════════

_gen_wg_and_paths() {
    WG_PRIV=$(wg genkey)
    WG_PUB=$(echo "$WG_PRIV" | wg pubkey)

    _rnd() { openssl rand -hex "$1" | head -c $((2 * $1)); }
    VLESS_PATH=$(_rnd 6)
    VMESS_PATH=$(_rnd 6)
    TROJAN_PATH=$(_rnd 6)
    SS_PATH=$(_rnd 6)
    GRPC_SUFFIX=$(_rnd 4)
    WS_SUFFIX=$(_rnd 4)

    # AmneziaWG server keys (same Curve25519 format)
    AWG_SERVER_PRIV=$(wg genkey)
    AWG_SERVER_PUB=$(echo "$AWG_SERVER_PRIV" | wg pubkey)

    # AmneziaWG obfuscation parameters
    AWG_JC=4; AWG_JMIN=40; AWG_JMAX=70; AWG_S1=0; AWG_S2=0

    _gen_awg_h() {
        local val
        val=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' \n')
        if [ -z "$val" ] || ! [ "$val" -gt 4 ] 2>/dev/null; then
            val=$(( (RANDOM * 32768 + RANDOM) + 100 ))
        fi
        echo "$val"
    }
    AWG_H1=$(_gen_awg_h); AWG_H2=$(_gen_awg_h)
    AWG_H3=$(_gen_awg_h); AWG_H4=$(_gen_awg_h)
}

STEP_CURRENT=$(( STEP_CURRENT + 1 ))
STEP_START_TIME=$(date +%s%N 2>/dev/null) || STEP_START_TIME=$(($(date +%s) * 1000000000))
_start_spinner "Generating WireGuard keys & Xray paths"
if _gen_wg_and_paths 2>/tmp/vpn-wg.err; then
    _finish_step ok "Generating WireGuard keys & Xray paths"
else
    _finish_step fail "Generating WireGuard keys & Xray paths"
    cat /tmp/vpn-wg.err | sed 's/^/    /'
    exit 1
fi

# ══════════════════════════════════════════════════════════
#  Step 7 — Write all config files
# ══════════════════════════════════════════════════════════

_write_configs() {
# ── HAProxy ──
cat > "$CONFIGS_DIR/haproxy/haproxy.cfg" <<EOF
global
    log stdout format raw local0
    maxconn 4096

defaults
    log     global
    mode    tcp
    option  tcplog
    timeout connect 10s
    timeout client  300s
    timeout server  300s

frontend ft_openvpn_tcp
    bind *:8080
    mode tcp
    default_backend bk_openvpn_tcp

backend bk_openvpn_tcp
    mode tcp
    server ovpn-tcp 127.0.0.1:11194 check
EOF

# ── Nginx ──
cat > "$CONFIGS_DIR/nginx/nginx.conf" <<EOF
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 10m;
    include /etc/nginx/conf.d/*.conf;
}
EOF

cat > "$CONFIGS_DIR/nginx/panel.conf" <<EOF
server {
    listen 8443 ssl;
    server_name $PUBLIC_HOST _;
    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    root /usr/share/nginx/html;
    index index.html;

    location /api/ {
        proxy_pass http://backend:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /share/ {
        try_files \$uri /index.html;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /${VLESS_PATH}${WS_SUFFIX} {
        proxy_pass http://xray:8444;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }
    location /${VMESS_PATH}${WS_SUFFIX} {
        proxy_pass http://xray:8445;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }
    location /${TROJAN_PATH}${WS_SUFFIX} {
        proxy_pass http://xray:8446;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_read_timeout 300s;
    }
}
EOF

# ── OpenVPN TCP ──
cat > "$CONFIGS_DIR/openvpn/server-tcp.conf" <<EOF
port 11194
proto tcp
dev tun0
topology subnet
ca /etc/openvpn/certs/ca.crt
cert /etc/openvpn/certs/server.crt
key /etc/openvpn/certs/server.key
dh /etc/openvpn/certs/dh.pem
tls-auth /etc/openvpn/certs/ta.key 0
server 10.8.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 120
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /etc/openvpn/data/status-tcp.log
verb 3
auth-user-pass-verify /etc/openvpn/data/auth.sh via-env
script-security 3
verify-client-cert none
username-as-common-name
EOF

# ── OpenVPN UDP ──
cat > "$CONFIGS_DIR/openvpn/server-udp.conf" <<EOF
port 1194
proto udp
dev tun1
topology subnet
ca /etc/openvpn/certs/ca.crt
cert /etc/openvpn/certs/server.crt
key /etc/openvpn/certs/server.key
dh /etc/openvpn/certs/dh.pem
tls-auth /etc/openvpn/certs/ta.key 0
server 10.9.0.0 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 1.1.1.1"
keepalive 10 120
cipher AES-256-GCM
auth SHA256
user nobody
group nogroup
persist-key
persist-tun
status /etc/openvpn/data/status-udp.log
verb 3
auth-user-pass-verify /etc/openvpn/data/auth.sh via-env
script-security 3
verify-client-cert none
username-as-common-name
EOF

# ── OpenVPN auth script ──
cat > "$DATA_DIR/openvpn/auth.sh" <<'AUTHEOF'
#!/bin/bash
curl -sf "http://127.0.0.1:18080/api/internal/auth-check" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$username\",\"password\":\"$password\",\"protocol\":\"openvpn\"}" \
    && exit 0
exit 1
AUTHEOF
chmod +x "$DATA_DIR/openvpn/auth.sh"

# ── WireGuard ──
cat > "$CONFIGS_DIR/wireguard/wg0.conf" <<EOF
[Interface]
Address = 10.66.66.1/24
ListenPort = 51820
PrivateKey = $WG_PRIV
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF

# ── IKEv2 ──
cat > "$CONFIGS_DIR/ikev2/swanctl.conf" <<EOF
connections {
    ikev2-vpn {
        version = 2
        local_addrs = 0.0.0.0
        fragmentation = yes
        mobike = yes
        proposals = aes256-sha256-modp2048,aes128-sha256-modp2048,aes256gcm16-prfsha256-ecp256,aes128gcm16-prfsha256-ecp256
        pools = vpn-pool
        dpd_delay = 300s
        rekey_time = 0s

        local {
            auth = pubkey
            id = $PUBLIC_HOST
            certs = ikev2-server.crt
        }

        remote {
            auth = eap-mschapv2
            eap_id = %any
        }

        children {
            net {
                local_ts = 0.0.0.0/0,::/0
                start_action = none
                dpd_action = clear
                esp_proposals = aes256gcm16,aes128gcm16,aes256-sha256,aes128-sha256
            }
        }
    }
}

pools {
    vpn-pool {
        addrs = 10.10.10.0/24
        dns = 8.8.8.8,1.1.1.1
    }
}

include conf.d/*.conf
EOF

cat > "$CONFIGS_DIR/ikev2/users.conf" <<EOF
secrets {
}
EOF

cat > "$CONFIGS_DIR/ikev2/strongswan.conf" <<EOF
charon {
    load_modular = yes
    plugins {
        include strongswan.d/charon/*.conf
        eap-dynamic {
            prefer_user = yes
            preferred = mschapv2
        }
    }
}
include strongswan.d/*.conf
EOF

# ── Xray ──
cat > "$CONFIGS_DIR/xray/config.json" <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "tag": "vless-ws",
      "listen": "0.0.0.0",
      "port": 8444,
      "protocol": "vless",
      "settings": {
        "clients": [{"id": "$XRAY_UUID", "email": "default@vpn-panel"}],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/${VLESS_PATH}${WS_SUFFIX}"}
      }
    },
    {
      "tag": "vmess-ws",
      "listen": "0.0.0.0",
      "port": 8445,
      "protocol": "vmess",
      "settings": {
        "clients": [{"id": "$XRAY_UUID", "email": "default@vpn-panel"}]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/${VMESS_PATH}${WS_SUFFIX}"}
      }
    },
    {
      "tag": "trojan-ws",
      "listen": "0.0.0.0",
      "port": 8446,
      "protocol": "trojan",
      "settings": {
        "clients": [{"password": "$XRAY_UUID", "email": "default@vpn-panel"}]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/${TROJAN_PATH}${WS_SUFFIX}"}
      }
    },
    {
      "tag": "shadowsocks",
      "listen": "0.0.0.0",
      "port": 8447,
      "protocol": "shadowsocks",
      "settings": {
        "method": "chacha20-ietf-poly1305",
        "password": "$SS_PASSWORD",
        "network": "tcp,udp"
      }
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "tag": "direct"},
    {"protocol": "blackhole", "tag": "blocked"}
  ]
}
EOF

# ── OpenConnect ──
cat > "$CONFIGS_DIR/openconnect/ocserv.conf" <<EOF
auth = "plain[passwd=/etc/ocserv/data/passwd]"
tcp-port = 443
socket-file = /var/run/ocserv-socket
run-as-user = nobody
run-as-group = nogroup
server-cert = /etc/ocserv/certs/server.crt
server-key = /etc/ocserv/certs/server.key
ca-cert = /etc/ocserv/certs/ca.crt
isolate-workers = true
max-clients = 128
max-same-clients = 2
keepalive = 32400
dpd = 90
mobile-dpd = 1800
try-mtu-discovery = false
tls-priorities = "NORMAL:%SERVER_PRECEDENCE:%COMPAT:-VERS-SSL3.0:-VERS-TLS1.0:-VERS-TLS1.1"
auth-timeout = 240
cookie-timeout = 300
rekey-time = 172800
rekey-method = ssl
use-occtl = true
device = vpns
predictable-ips = true
default-domain = $SERVER_IP
ipv4-network = 10.20.20.0/24
dns = 8.8.8.8
route = default
cisco-client-compat = true
dtls-legacy = true
EOF

touch "$DATA_DIR/openconnect/passwd"

# ── AmneziaWG ──
cat > "$CONFIGS_DIR/amneziawg/awg0.conf" <<EOF
[Interface]
Address = 10.66.67.1/24
ListenPort = 51821
PrivateKey = $AWG_SERVER_PRIV
Jc = $AWG_JC
Jmin = $AWG_JMIN
Jmax = $AWG_JMAX
S1 = $AWG_S1
S2 = $AWG_S2
H1 = $AWG_H1
H2 = $AWG_H2
H3 = $AWG_H3
H4 = $AWG_H4
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
EOF
}

task "Writing protocol configuration files" _write_configs

# ══════════════════════════════════════════════════════════
#  Step 8 — Backend config.json
# ══════════════════════════════════════════════════════════

_write_backend_config() {
cat > "$DATA_DIR/config.json" <<EOF
{
  "data_dir": "/opt/vpn-panel/data",
  "certs_dir": "/opt/vpn-panel/certs",
  "configs_dir": "/opt/vpn-panel/configs",
  "web_dir": "/opt/vpn-panel/web",
  "server_ip": "$PUBLIC_HOST",
  "listen_addr": ":8080",
  "admin_user": "$ADMIN_USER",
  "admin_pass_hash": "$ADMIN_PASS_HASH",
  "session_secret": "$SESSION_SECRET",
  "wireguard": {
    "server_private_key": "$WG_PRIV",
    "server_public_key": "$WG_PUB",
    "port": 51820,
    "subnet": "10.66.66.0/24",
    "server_address": "10.66.66.1",
    "dns": "8.8.8.8, 1.1.1.1"
  },
  "openvpn": {
    "tcp_ports": [11194],
    "udp_ports": [1194],
    "subnet": "10.8.0.0/24",
    "dns": "8.8.8.8"
  },
  "ikev2": {
    "subnet": "10.10.10.0/24",
    "dns": "8.8.8.8, 1.1.1.1"
  },
  "xray": {
    "uuid": "$XRAY_UUID",
    "paths": {
      "vless_path": "$VLESS_PATH",
      "vmess_path": "$VMESS_PATH",
      "trojan_path": "$TROJAN_PATH",
      "ss_path": "$SS_PATH",
      "grpc_path": "$GRPC_SUFFIX",
      "ws_path": "$WS_SUFFIX",
      "tcp_h2_path": "",
      "httpupgrade_path": "",
      "utility_path": ""
    },
    "reality_sni": "",
    "reality_pbk": "",
    "reality_sid": "",
    "reality_priv": "",
    "ss_password": "$SS_PASSWORD",
    "ss_method": "chacha20-ietf-poly1305"
  },
  "openconnect": {
    "port": 443,
    "subnet": "10.20.20.0/24",
    "dns": "8.8.8.8"
  },
  "amneziawg": {
    "server_private_key": "$AWG_SERVER_PRIV",
    "server_public_key": "$AWG_SERVER_PUB",
    "port": 51821,
    "subnet": "10.66.67.0/24",
    "server_address": "10.66.67.1",
    "dns": "8.8.8.8, 1.1.1.1",
    "jc": $AWG_JC,
    "jmin": $AWG_JMIN,
    "jmax": $AWG_JMAX,
    "s1": $AWG_S1,
    "s2": $AWG_S2,
    "h1": $AWG_H1,
    "h2": $AWG_H2,
    "h3": $AWG_H3,
    "h4": $AWG_H4
  }
}
EOF
}

task "Writing backend configuration" _write_backend_config

# ──────────────────────────────────────────────────────────
#  Fetch deployment bundle when running standalone
# ──────────────────────────────────────────────────────────

_fetch_release_bundle() {
    [ -f "$SCRIPT_DIR/docker-compose.yml" ] && [ -d "$SCRIPT_DIR/cmd" ] && return 0

    local bundle_dir bundle_url tmp_bundle
    bundle_dir=$(mktemp -d)
    bundle_url="https://github.com/${PUBLIC_RELEASE_REPO}/releases/latest/download/${PUBLIC_RELEASE_BUNDLE}"
    tmp_bundle="$bundle_dir/${PUBLIC_RELEASE_BUNDLE}"

    curl -fsSL "$bundle_url" -o "$tmp_bundle"
    tar -xzf "$tmp_bundle" -C "$bundle_dir"
    SCRIPT_DIR="$bundle_dir"
}

# (not counted in STEP_TOTAL — near-instant)
_fetch_release_bundle

# ──────────────────────────────────────────────────────────
#  Copy project source files
# ──────────────────────────────────────────────────────────

_copy_source() {
    if [ "$SCRIPT_DIR" = "$INSTALL_DIR" ]; then
        return 0
    fi
    cp "$SCRIPT_DIR/docker-compose.yml" "$INSTALL_DIR/"
    cp -r "$SCRIPT_DIR/docker" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/Dockerfile" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/go.mod" "$INSTALL_DIR/"
    cp "$SCRIPT_DIR/go.sum" "$INSTALL_DIR/"
    cp -r "$SCRIPT_DIR/cmd" "$INSTALL_DIR/"
    cp -r "$SCRIPT_DIR/internal" "$INSTALL_DIR/"
    cp -r "$SCRIPT_DIR/web" "$INSTALL_DIR/"
}

# (not counted in STEP_TOTAL — near-instant)
STEP_CURRENT=$(( STEP_CURRENT + 0 ))  # no increment; absorbed into step 8
_copy_source

# ══════════════════════════════════════════════════════════
#  Step 9 — Build & launch containers
# ══════════════════════════════════════════════════════════

_docker_build() {
    cd "$INSTALL_DIR"
    local build_services=(backend openvpn-tcp openvpn-udp ikev2 amneziawg openconnect)
    if [ "${USE_PREBUILT_IMAGES:-1}" = "1" ] && docker compose pull "${build_services[@]}" >/dev/null 2>&1; then
        docker compose up -d --no-build --force-recreate --remove-orphans 2>&1
        return 0
    fi

    docker compose build --parallel "${build_services[@]}" 2>&1
    docker compose up -d --force-recreate --remove-orphans 2>&1
}

task "Building & launching containers" _docker_build

# ══════════════════════════════════════════════════════════
#  Step 10 — Initialize default user
# ══════════════════════════════════════════════════════════

_wait_and_init() {
    # Wait up to 60s for backend
    for i in $(seq 1 30); do
        if curl -s -o /dev/null http://127.0.0.1:18080/api/dashboard; then
            break
        fi
        sleep 2
    done
    # Create default user
    INIT_RESULT=$(curl -sf -X POST http://127.0.0.1:18080/api/internal/init 2>/dev/null || echo '{}')
    SHARE_URL=$(echo "$INIT_RESULT" | \
        python3 -c "import sys,json; print(json.load(sys.stdin).get('share_url',''))" \
        2>/dev/null || echo "")
}

STEP_CURRENT=$(( STEP_CURRENT + 1 ))
STEP_START_TIME=$(date +%s%N 2>/dev/null) || STEP_START_TIME=$(($(date +%s) * 1000000000))
_start_spinner "Waiting for backend & creating default user"
SHARE_URL=""
INIT_RESULT=""
if _wait_and_init 2>/tmp/vpn-init.err; then
    _finish_step ok "Waiting for backend & creating default user"
else
    _finish_step fail "Waiting for backend & creating default user"
    cat /tmp/vpn-init.err | sed 's/^/    /'
    exit 1
fi

# ══════════════════════════════════════════════════════════
#  Summary
# ══════════════════════════════════════════════════════════

echo ""
echo -e "  ${BOLD}${GREEN}┌──────────────────────────────────────────────────────┐${NC}"
echo -e "  ${BOLD}${GREEN}│${NC}  ${BOLD}${WHITE}✓  DigitalD.tech VPN Panel installed successfully${NC}                  ${BOLD}${GREEN}│${NC}"
echo -e "  ${BOLD}${GREEN}└──────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${BOLD}${WHITE}Access${NC}"
echo -e "  ${DIM}──────────────────────────────────────${NC}"
echo -e "  ${DIM}Panel URL${NC}    ${CYAN}https://${PUBLIC_HOST}:8443/${NC}"
echo -e "  ${DIM}Username${NC}     ${WHITE}${ADMIN_USER}${NC}"
echo -e "  ${DIM}Password${NC}     ${BOLD}${WHITE}${ADMIN_PASS}${NC}"
echo ""
if [ -n "$SHARE_URL" ]; then
echo -e "  ${BOLD}${WHITE}Default User Configs${NC}"
echo -e "  ${DIM}──────────────────────────────────────${NC}"
echo -e "  ${CYAN}${SHARE_URL}${NC}"
echo ""
fi
echo -e "  ${BOLD}${WHITE}Protocols${NC}"
echo -e "  ${DIM}──────────────────────────────────────${NC}"
echo -e "  ${GREEN}${SYM_DOT}${NC}  OpenVPN TCP    ${DIM}11194${NC}"
echo -e "  ${GREEN}${SYM_DOT}${NC}  OpenVPN UDP    ${DIM}1194${NC}"
echo -e "  ${GREEN}${SYM_DOT}${NC}  WireGuard      ${DIM}51820/UDP${NC}"
echo -e "  ${GREEN}${SYM_DOT}${NC}  IKEv2          ${DIM}500/UDP, 4500/UDP${NC}"
echo -e "  ${GREEN}${SYM_DOT}${NC}  Xray (Hiddify) ${DIM}8443 via Nginx (WS only)${NC}"
echo -e "  ${GREEN}${SYM_DOT}${NC}  OpenConnect    ${DIM}443 direct${NC}"
echo -e "  ${GREEN}${SYM_DOT}${NC}  AmneziaWG      ${DIM}51821/UDP (obfuscated)${NC}"
echo ""
echo -e "  ${DIM}Note: Accept the self-signed certificate in your browser.${NC}"
echo ""
