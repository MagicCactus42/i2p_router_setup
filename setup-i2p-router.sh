#!/bin/bash
set -euo pipefail

# ==============================================================================
#  DietPi I2P Router + Tailscale — Automated Setup
#  Po uruchomieniu jedyne co zostaje to: tailscale up --ssh
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# --- Sprawdzenie ---
[[ $EUID -ne 0 ]] && err "Uruchom jako root: sudo bash $0"

# --- Wykryj Debian codename ---
CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
[[ -z "$CODENAME" ]] && err "Nie udało się wykryć codename Debiana."
log "Wykryty Debian: $CODENAME"

# --- Wykryj podsieć i interfejs ---
IFACE=$(ip route show default | awk '{print $5}' | head -1)
SUBNET=$(ip -4 addr show "$IFACE" | awk '/inet /{print $2}' | head -1 | sed 's|\.[0-9]*/|.0/|')

if [[ -z "$IFACE" || -z "$SUBNET" ]]; then
    err "Nie udało się wykryć interfejsu lub podsieci. Sprawdź połączenie sieciowe."
fi

log "Wykryty interfejs: $IFACE"
log "Wykryta podsieć:   $SUBNET"

# --- Konfigurowalny port transit ---
I2PD_PORT="${I2PD_PORT:-12345}"
log "Port transit i2pd: $I2PD_PORT"

echo ""
warn "Setup zacznie się za 5 sekund. Ctrl+C żeby przerwać."
sleep 5

# ==============================================================================
#  1. INSTALACJA i2pd
# ==============================================================================
log "Instaluję i2pd..."

apt-get update -qq
apt-get install -y -qq apt-transport-https curl gnupg > /dev/null

curl -fsSL https://repo.i2pd.xyz/r4sas.gpg | gpg --batch --yes --dearmor -o /usr/share/keyrings/i2pd.gpg

# Próbuj repo dla wykrytego codename, fallback na bookworm
I2PD_INSTALLED=false
for try_codename in "$CODENAME" bookworm; do
    log "Próbuję repo i2pd dla: $try_codename"
    echo "deb [signed-by=/usr/share/keyrings/i2pd.gpg] https://repo.i2pd.xyz/debian ${try_codename} main" \
        > /etc/apt/sources.list.d/i2pd.list
    apt-get update -qq
    if apt-get install -y i2pd > /dev/null 2>&1; then
        I2PD_INSTALLED=true
        log "i2pd zainstalowany z repo: $try_codename"
        break
    else
        warn "Brak kompatybilnej paczki dla $try_codename, próbuję dalej..."
    fi
done

$I2PD_INSTALLED || err "Nie udało się zainstalować i2pd z żadnego repo. Sprawdź ręcznie."

systemctl stop i2pd

# ==============================================================================
#  2. INSTALACJA Tailscale
# ==============================================================================
log "Instaluję Tailscale..."

if ! command -v tailscale &> /dev/null; then
    curl -fsSL https://tailscale.com/install.sh | sh
fi

systemctl enable --now tailscaled

log "Tailscale zainstalowany."

# ==============================================================================
#  3. KONFIGURACJA i2pd
# ==============================================================================
log "Konfiguruję i2pd..."

cat > /etc/i2pd/i2pd.conf << EOF
# Wygenerowane przez setup script

[http]
enabled = true
address = 0.0.0.0
port = 7070

[httpproxy]
enabled = true
address = 0.0.0.0
port = 4444

[socksproxy]
enabled = false

[sam]
enabled = false

[ntcp2]
enabled = true
port = ${I2PD_PORT}

[ssu2]
enabled = true
port = ${I2PD_PORT}

[limits]
transittunnels = 2500
EOF

systemctl enable i2pd

log "i2pd skonfigurowany."

# ==============================================================================
#  4. WYŁĄCZ OpenSSH
# ==============================================================================
log "Wyłączam OpenSSH (Tailscale SSH go zastąpi)..."

if systemctl is-active --quiet ssh 2>/dev/null; then
    systemctl disable --now ssh
    log "OpenSSH wyłączony."
else
    log "OpenSSH już nieaktywny — pomijam."
fi

# ==============================================================================
#  5. FIREWALL (UFW)
# ==============================================================================
log "Konfiguruję UFW..."

apt-get install -y -qq ufw > /dev/null

# Reset na czysto
ufw --force reset > /dev/null

ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null

# Transit i2pd — publiczny UDP (SSU2) + TCP (NTCP2)
ufw allow in on "$IFACE" proto udp to any port "$I2PD_PORT" > /dev/null
ufw allow in on "$IFACE" proto tcp to any port "$I2PD_PORT" > /dev/null

# HTTP Proxy — LAN + Tailscale
ufw allow in on "$IFACE" from "$SUBNET" to any port 4444 proto tcp > /dev/null
ufw allow in on tailscale0 to any port 4444 proto tcp > /dev/null

# Webconsole — LAN + Tailscale
ufw allow in on "$IFACE" from "$SUBNET" to any port 7070 proto tcp > /dev/null
ufw allow in on tailscale0 to any port 7070 proto tcp > /dev/null

# Tailscale — cały ruch z tailnet
ufw allow in on tailscale0 > /dev/null

ufw --force enable > /dev/null

log "UFW skonfigurowany."

# ==============================================================================
#  6. SYSCTL HARDENING
# ==============================================================================
log "Hardening sysctl..."

cat > /etc/sysctl.d/90-hardening.conf << 'EOF'
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.log_martians = 1
kernel.unprivileged_bpf_disabled = 1
kernel.kptr_restrict = 2
EOF

sysctl --system > /dev/null 2>&1

log "sysctl zastosowany."

# ==============================================================================
#  7. PORZĄDKI
# ==============================================================================
log "Wyłączam zbędne serwisy..."

for svc in avahi-daemon bluetooth; do
    if systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        systemctl disable --now "$svc" > /dev/null 2>&1
        log "  Wyłączono: $svc"
    fi
done

# ==============================================================================
#  8. UNATTENDED UPGRADES
# ==============================================================================
log "Konfiguruję auto-updaty bezpieczeństwa..."

apt-get install -y -qq unattended-upgrades > /dev/null

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

log "Auto-updaty włączone."

# ==============================================================================
#  9. START i2pd
# ==============================================================================
log "Startuję i2pd..."
systemctl start i2pd

# ==============================================================================
#  PODSUMOWANIE
# ==============================================================================
echo ""
echo "============================================================"
echo -e "${GREEN}  SETUP ZAKOŃCZONY${NC}"
echo "============================================================"
echo ""
echo "  Został JEDEN krok — zaloguj się do Tailscale:"
echo ""
echo -e "    ${YELLOW}tailscale up --ssh${NC}"
echo ""
echo "  Następnie w przeglądarce ustaw HTTP proxy na:"
echo ""
echo "    Z LAN:       $(ip -4 addr show "$IFACE" | awk '/inet /{print $2}' | cut -d/ -f1):4444"
echo "    Z Tailscale:  <twój_tailscale_ip>:4444"
echo ""
echo "  Webconsole:"
echo "    http://$(ip -4 addr show "$IFACE" | awk '/inet /{print $2}' | cut -d/ -f1):7070"
echo ""
echo "  UFW status:"
ufw status numbered
echo ""
echo "  Daj i2pd kilka minut na zbudowanie tuneli."
echo "============================================================"
