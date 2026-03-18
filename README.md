# NORYPT Privacy

**Boot-time identity randomization for the GL-iNet Puli AX (GL-XE3000)**

On every boot, NORYPT Privacy automatically randomizes your cellular modem IMEI, Wi-Fi BSSIDs, and WAN MAC address using real manufacturer OUI and TAC databases — so every power cycle looks like a completely different device to cell towers, access points, and network observers.

---

## Features

- **IMEI randomization** — generates a valid 15-digit IMEI using real phone TAC codes and a correct Luhn checksum
- **Wi-Fi BSSID randomization** — assigns a new MAC per radio using real wireless chipset OUIs
- **WAN MAC randomization** — changes the WAN interface MAC using real NIC vendor OUIs
- **Full log wipe** — clears all syslog, kernel log, and temp log locations on boot
- **Dark web panel** — browser UI at `http://192.168.8.1/norypt/` with live status, toggles, and history
- **CLI tool** — `norypt` command for status, manual randomization, and config
- **sysupgrade persistence** — survives GL-iNet/OpenWrt firmware upgrades
- **OpenWrt package** — ships as a `.ipk` via Makefile, or a one-command SSH installer

---

## Supported Hardware

| Device | Status |
|--------|--------|
| GL-iNet Puli AX (GL-XE3000) | Fully supported |
| GL-iNet firmware v4.5+ | Fully supported |
| GL-iNet firmware v4.x (< 4.5) | Supported |
| Vanilla OpenWrt (MediaTek Filogic) | Supported |

**Modem:** Quectel RM520N-GL (port `/dev/ttyUSB2`, CDC-WDM `/dev/cdc-wdm0`)

---

## Installation

### Method 1 — One-command SSH installer (online)

SSH into your router and run:

```sh
wget -O - https://raw.githubusercontent.com/dartonverhovan-ctrl/norypt-privacy/main/install.sh | sh
```

Or with curl:

```sh
curl -fsSL https://raw.githubusercontent.com/dartonverhovan-ctrl/norypt-privacy/main/install.sh | sh
```

The installer will:
1. Check and install missing dependencies (`uqmi`, `bash`, `coreutils-shuf`) via opkg
2. Download all modules, databases, and web panel files
3. Enable and start the service immediately
4. Configure the uhttpd redirect for the web panel
5. Set up sysupgrade persistence

---

### Method 2 — Manual offline installation

**Step 1:** Download or clone this repository on your computer:

```sh
git clone https://github.com/dartonverhovan-ctrl/norypt-privacy.git
```

**Step 2:** Copy files to the router over SCP. Replace `192.168.8.1` with your router IP:

```sh
cd norypt-privacy

# Modules and databases
scp -r src/modules src/db root@192.168.8.1:/etc/norypt/

# Web panel
scp -r src/www root@192.168.8.1:/www/norypt

# CGI backend
scp src/cgi-bin/norypt.cgi root@192.168.8.1:/www/cgi-bin/norypt.cgi

# Service files
scp src/init.d/norypt root@192.168.8.1:/etc/init.d/norypt
scp src/uci-defaults/99-norypt root@192.168.8.1:/etc/uci-defaults/99-norypt
scp src/bin/norypt root@192.168.8.1:/usr/bin/norypt
scp src/config/norypt root@192.168.8.1:/etc/config/norypt
```

**Step 3:** SSH into the router and set permissions:

```sh
ssh root@192.168.8.1

chmod 755 /etc/norypt/*.sh
chmod 755 /etc/init.d/norypt /etc/uci-defaults/99-norypt /usr/bin/norypt /www/cgi-bin/norypt.cgi
chmod 644 /etc/norypt/*.db /etc/config/norypt
chmod 644 /www/norypt/*
```

**Step 4:** Install dependencies (requires internet on router, or pre-download the ipk files):

```sh
opkg update
opkg install uqmi bash coreutils-shuf
```

**Step 5:** Enable and start the service:

```sh
/etc/init.d/norypt enable
/etc/init.d/norypt start
```

**Step 6:** Configure the uhttpd web panel redirect:

```sh
uci add uhttpd redirect
uci set uhttpd.@redirect[-1].name='norypt_redirect'
uci set uhttpd.@redirect[-1].from='/norypt/'
uci set uhttpd.@redirect[-1].to='/cgi-bin/norypt.cgi?action=serve_index'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

**Step 7:** Set up sysupgrade persistence:

```sh
cat >> /etc/sysupgrade.conf << 'EOF'
/etc/norypt/
/etc/config/norypt
/etc/init.d/norypt
/etc/uci-defaults/99-norypt
/usr/bin/norypt
/www/cgi-bin/norypt.cgi
/www/norypt/
EOF
```

---

### Method 3 — OpenWrt package (ipk build)

Build from within an OpenWrt SDK:

```sh
# Copy package directory into your OpenWrt feeds
cp -r norypt-privacy /path/to/openwrt/package/

# Build
cd /path/to/openwrt
make package/norypt-privacy/compile V=s

# Install the resulting .ipk on the router
opkg install bin/packages/.../norypt-privacy_1.0.0-1_all.ipk
```

---

## Uninstall

SSH into the router and run:

```sh
wget -O - https://raw.githubusercontent.com/dartonverhovan-ctrl/norypt-privacy/main/uninstall.sh | sh
```

Or manually:

```sh
/etc/init.d/norypt stop
/etc/init.d/norypt disable
rm -rf /etc/norypt /www/norypt
rm -f /etc/init.d/norypt /usr/bin/norypt /www/cgi-bin/norypt.cgi
rm -f /etc/config/norypt /etc/uci-defaults/99-norypt
sed -i '/norypt/d' /etc/sysupgrade.conf
```

---

## Web Panel

Open `http://192.168.8.1/norypt/` in your browser after installation.

The panel shows:
- Current IMEI, BSSID (2.4 GHz / 5 GHz), WAN MAC
- Cellular connection status and firmware version
- Feature toggles (enable/disable each randomization)
- Randomize now / Wipe logs buttons
- Boot history log

---

## CLI Reference

```
norypt status                          Show IMEI, MACs, cellular, config
norypt randomize [imei|bssid|wan|all]  Randomize identities (default: all)
norypt wipe-logs                       Wipe all system log locations
norypt config show                     Dump current config
norypt config set <key> <on|off>       Toggle a feature
norypt service <start|stop|restart|status>
norypt version                         Show version and firmware info
norypt help                            Show help
```

### Config keys

| Key | Default | Description |
|-----|---------|-------------|
| `enabled` | `1` | Master on/off switch |
| `randomize_imei` | `1` | Randomize modem IMEI on boot |
| `randomize_bssid` | `1` | Randomize Wi-Fi BSSIDs on boot |
| `randomize_wan` | `1` | Randomize WAN MAC on boot |
| `wipe_logs` | `1` | Wipe all logs on boot |
| `wipe_dhcp` | `1` | Wipe DHCP leases on boot |
| `on_boot` | `1` | Run automatically at boot |
| `settle_delay` | `3` | Seconds to wait after modem init |
| `cellular_timeout` | `60` | Seconds to wait for cellular IP |
| `log_history` | `10` | Number of boot events to keep |

Example:

```sh
norypt config set randomize_imei on
norypt config set wipe_logs off
```

---

## How It Works

1. **IMEI** — selects a random TAC (Type Allocation Code) from a database of 220 real phone TAC codes, appends 6 random digits, and computes the correct Luhn check digit. The result is a valid 15-digit IMEI. Sent to the modem via AT commands: `AT+QCFG="IMEI/LOCK",0` then `AT+EGMR=1,7,"<imei>"`.

2. **BSSID** — selects a random OUI from 48 real wireless chipset manufacturers, appends 3 random bytes. First byte: bit 0 = 0 (unicast), bit 1 = 0 (globally unique). Applied via `ip link set` and UCI commit.

3. **WAN MAC** — same OUI approach using 45 real NIC/router vendor OUIs. Applied at boot before DHCP negotiation.

4. **Log wipe** — removes files in `/var/log/`, `/tmp/log/`, clears the kernel ring buffer, and restarts the syslog daemon.

5. **Boot order** — the procd init service runs at `START=19`, before the network service at `START=20`, ensuring MACs are set before any DHCP or cellular registration.

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `uqmi` | Read current IMEI via `--get-imei` |
| `bash` | Required by IMEI randomization module (AT serial I/O) |
| `coreutils-shuf` | Unbiased random selection from OUI/TAC databases |

All other tools (`ip`, `uci`, `wifi`, `ifup`, `ifdown`) are included in standard OpenWrt/GL-iNet firmware.

---

## Project Structure

```
norypt-privacy/
├── src/
│   ├── modules/            # Shell modules (imei, mac, log, cellular, etc.)
│   ├── db/                 # TAC and OUI databases
│   ├── bin/norypt          # CLI tool
│   ├── cgi-bin/norypt.cgi  # Web panel backend (CGI, CSRF-protected)
│   ├── www/                # Web panel frontend (HTML/CSS/JS)
│   ├── init.d/norypt       # procd service definition
│   ├── uci-defaults/99-norypt  # First-boot and sysupgrade hook
│   └── config/norypt       # UCI config defaults
├── tests/                  # bats-core test suite (74 tests)
├── install.sh              # One-command SSH installer
├── uninstall.sh            # Clean uninstaller
└── Makefile                # OpenWrt package build
```

---

## Security Notes

- The web panel is only accessible on the LAN interface — it is not exposed to WAN or cellular
- All web panel requests are CSRF-protected via a per-session token (`X-Norypt-Token` header)
- No external connections are made at runtime — all randomization is fully local
- Randomized identities use real OUI/TAC prefixes to avoid detection as spoofed addresses

---

## Made by NORYPT

This project is part of the NORYPT privacy toolkit.
Open-source. Use responsibly.
