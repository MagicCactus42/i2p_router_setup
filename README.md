# I2P Router + Tailscale — Automated Setup (DietPi / Raspberry Pi)

## PL

### Co robi ten skrypt?

Skrypt automatycznie konfiguruje Raspberry Pi (DietPi/Debian) jako router I2P z bezpiecznym zdalnym dostepem przez Tailscale. Konkretnie:

- Instaluje **i2pd** (router I2P) i **Tailscale** (VPN mesh)
- Konfiguruje i2pd z HTTP proxy (`:4444`) i webconsole (`:7070`)
- Ustawia **firewall (UFW)** — wpuszcza tylko ruch i2pd, LAN i Tailscale
- **Wylacza OpenSSH** (zastepuje go Tailscale SSH)
- Stosuje **hardening sysctl** i wlacza **automatyczne aktualizacje bezpieczenstwa**
- Wylacza zbedne serwisy (avahi, bluetooth)

Po zakonczeniu jedyne co trzeba zrobic recznie to `tailscale up --ssh`.

### Przenoszenie na Raspberry Pi przez SSH

```bash
# 1. Skopiuj skrypt na Pi
scp setup-i2p-router.sh user@<IP_PI>:~/

# 2. Zaloguj sie na Pi
ssh user@<IP_PI>

# 3. Uruchom skrypt jako root
sudo bash setup-i2p-router.sh

# 4. Po zakonczeniu — zaloguj sie do Tailscale
tailscale up --ssh
```

### Zmienne konfiguracyjne

Port i2pd (domyslnie `12345`) mozna zmienic przez zmienna srodowiskowa `I2PD_PORT`:

```bash
sudo I2PD_PORT=9999 bash setup-i2p-router.sh
```

---

## EN

### What does this script do?

The script automatically configures a Raspberry Pi (DietPi/Debian) as an I2P router with secure remote access via Tailscale. Specifically:

- Installs **i2pd** (I2P router) and **Tailscale** (mesh VPN)
- Configures i2pd with HTTP proxy (`:4444`) and webconsole (`:7070`)
- Sets up **UFW firewall** — only allows i2pd transit, LAN, and Tailscale traffic
- **Disables OpenSSH** (replaced by Tailscale SSH)
- Applies **sysctl hardening** and enables **unattended security upgrades**
- Disables unnecessary services (avahi, bluetooth)

After completion, the only manual step is `tailscale up --ssh`.

### Deploying to Raspberry Pi via SSH

```bash
# 1. Copy the script to Pi
scp setup-i2p-router.sh user@<PI_IP>:~/

# 2. SSH into Pi
ssh user@<PI_IP>

# 3. Run the script as root
sudo bash setup-i2p-router.sh

# 4. After completion — log into Tailscale
tailscale up --ssh
```

### Configuration variables

The i2pd port (default `12345`) can be changed via the `I2PD_PORT` environment variable:

```bash
sudo I2PD_PORT=9999 bash setup-i2p-router.sh
```
