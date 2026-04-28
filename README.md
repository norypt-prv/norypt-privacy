<div align="center">

<img src="logo/norypt-icon-512_No_background.png" alt="NORYPT" width="180" />

# NORYPT Privacy

**Boot-time identity randomization for the GL-iNet Puli AX (GL-XE3000)**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](#license)
[![Platform: OpenWrt](https://img.shields.io/badge/platform-OpenWrt%20%2F%20GL--iNet-1f6feb.svg)](#supported-hardware)
[![Hardware: GL--XE3000](https://img.shields.io/badge/hardware-GL--XE3000-3fb950.svg)](#supported-hardware)
[![Shell](https://img.shields.io/badge/shell-bash%20%2F%20ash-yellow.svg)](#)

</div>

---

NORYPT Privacy turns the **GL-iNet Puli AX (GL-XE3000)** into a privacy-first travel router.
On every boot, NORYPT silently rotates the cellular **IMEI**, both Wi-Fi **BSSIDs**, and the **WAN MAC**
using **real manufacturer OUI and TAC databases** — so to every cell tower, captive portal, and
upstream observer, your router looks like a brand-new device on each power cycle.

It ships as a self-contained OpenWrt service with a dark web panel, a CLI, hotplug
re-application, sysupgrade persistence, and an offline-installable `.ipk` bundle.

---

## Table of Contents

1. [Features](#features)
2. [Supported Hardware](#supported-hardware)
3. [Installation](#installation)
4. [Web Panel](#web-panel)
5. [CLI Reference](#cli-reference)
6. [Configuration](#configuration)
7. [How It Works](#how-it-works)
8. [Architecture](#architecture)
9. [Project Structure](#project-structure)
10. [Security Notes](#security-notes)
11. [Uninstall](#uninstall)
12. [Contributors](#contributors)
13. [License](#license)

---

## Features

| Capability | Description |
|---|---|
| **IMEI randomization** | Generates a valid 15-digit IMEI from a 220-entry real phone TAC database with a correct Luhn check digit. Sent to the modem via `AT+EGMR=1,7,…` after `AT+QCFG="IMEI/LOCK",0`. |
| **Wi-Fi BSSID randomization** | Per-radio MAC reassignment on `2.4 GHz` and `5 GHz`, using 48 real wireless-chipset OUIs. Bits cleared for unicast + globally-unique. Applied via `ip link` and committed to UCI. |
| **WAN MAC randomization** | Pre-DHCP MAC swap on `eth0` from a 45-entry NIC/router OUI list. A hotplug script re-applies the MAC whenever `netifd` brings the WAN up, so daemons can't quietly reset it. |
| **Full log wipe** | Wipes `/var/log/`, `/tmp/log/`, dnsmasq leases, hostapd state, UCI deltas, then restarts the syslog service to flush the in-memory ring buffer. |
| **Boot-time execution** | Runs at `START=19` — before `network` (`START=20`) — so MACs land before any DHCP or cellular registration. |
| **Dark web panel** | Browser UI at `http://192.168.8.1/norypt/` — live status, per-feature toggles, manual randomization, and a 10-event boot history. CSRF-protected, LAN-only. |
| **CLI tool** | `norypt status / randomize / wipe-logs / config / service / version` — operates without the web panel. |
| **Sysupgrade persistence** | `/etc/sysupgrade.conf` entries auto-installed; survives GL-iNet/OpenWrt firmware upgrades. |
| **Hotplug re-application** | `/etc/hotplug.d/iface/99-norypt-wan` re-asserts the stored WAN MAC on every `ifup wan`. |
| **Online + offline install** | One-line SSH installer, full bundled `.ipk` set, and an OpenWrt SDK build target. |
| **Multi-server support** | Auto-detects `uhttpd` (vanilla OpenWrt) or `nginx + fcgiwrap` (GL-iNet 4.x) and configures the panel accordingly. |
| **Auto-detection** | Resolves Wi-Fi interface names (`ra0`/`rax0`/`wlan*`/`ath*`) and UCI section names (`wifi2g`/`wifi5g`/`radio0`/`radio1`) at runtime — works on both stock GL-iNet and vanilla OpenWrt. |

---

## Supported Hardware

| Device | Status |
|---|---|
| GL-iNet Puli AX (GL-XE3000) | **Fully supported** — primary target |
| GL-iNet firmware v4.5+ (`nginx`) | Fully supported |
| GL-iNet firmware v4.x (< 4.5) | Supported |
| Vanilla OpenWrt (MediaTek Filogic 820) | Supported |

**Cellular modem:** built-in Quectel EM060K-GL — accessible over `ubus AT` (GL-iNet) or `/dev/mhi_DUN` (vanilla).

---

## Installation

### Method 1 — One-command SSH installer (online)

```sh
wget -O - https://raw.githubusercontent.com/dartonverhovan-ctrl/norypt-privacy/main/install.sh | sh
```

The installer:
1. Detects firmware (GL-iNet vs vanilla OpenWrt).
2. Installs missing dependencies (`uqmi`, `bash`, `coreutils-shuf`) — and `fcgiwrap` if nginx is in use.
3. Downloads modules, OUI/TAC databases, web panel, CGI, init script, hotplug, and CLI.
4. Enables and starts the service immediately.
5. Configures the panel route — `uhttpd` redirect or `nginx` location block — automatically.
6. Sets up sysupgrade persistence.

### Method 2 — Offline pre-built `.ipk` bundle

If your router has no internet, the `offline/` folder ships every `.ipk` it needs:

```sh
# On your PC
git clone https://github.com/dartonverhovan-ctrl/norypt-privacy.git
scp -r norypt-privacy root@192.168.8.1:/tmp/norypt-privacy

# On the router (over SSH)
sh /tmp/norypt-privacy/offline/install-offline.sh
```

**Bundled packages** (OpenWrt 23.05.3 / `aarch64_cortex-a53`):

| Package | Version |
|---|---|
| `uqmi` | 2022-10-20 |
| `bash` | 5.2.15-1 |
| `coreutils-shuf` | 9.3-1 |
| `coreutils` | 9.3-1 |
| `libncurses6` | 6.4-2 |
| `libreadline8` | 8.2-1 |
| `libubox20230523` | 2023-05-23 |
| `libblobmsg-json20230523` | 2023-05-23 |
| `wwan` | 2019-04-29 |

> If you are on a different firmware build, the bundled `.ipk` files may conflict.
> Use Method 1, or download matching `.ipk` files from <https://downloads.openwrt.org/releases/>.

### Method 3 — OpenWrt SDK package

```sh
cp -r norypt-privacy /path/to/openwrt/package/
cd /path/to/openwrt
make package/norypt-privacy/compile V=s
opkg install bin/packages/.../norypt-privacy_1.0.0-1_all.ipk
```

---

## Web Panel

Open `http://192.168.8.1/norypt/` after installation.

The panel shows:

- **Current Identities** — IMEI, BSSID 2 GHz, BSSID 5 GHz, WAN MAC, and live cellular state.
- **Feature Toggles** — IMEI / BSSID / WAN-MAC randomization, log wipe on boot, run-on-boot.
  Toggles reflect the current UCI state on load — not always-checked placeholders.
- **Manual Controls** — randomize a single identity, randomize everything, wipe logs.
- **Last 10 Events** — boot and manual randomization history.

Every panel action carries a per-session CSRF token (`X-Norypt-Token` header) that is verified
server-side by `/www/cgi-bin/norypt.cgi`. The token store is `/tmp/norypt_csrf_<session>`.

---

## CLI Reference

```
norypt status                          Show IMEI, MACs, cellular, config
norypt randomize [imei|bssid|wan|all]  Randomize identities (default: all)
norypt wipe-logs                       Wipe all system log locations
norypt config show                     Dump current UCI config
norypt config set <key> <on|off|N>     Toggle a feature
norypt service <start|stop|restart|status>
norypt version                         Show version and firmware info
norypt help                            Show this help
```

Examples:

```sh
norypt status
norypt randomize bssid
norypt config set randomize_imei off
norypt config set settle_delay 5
```

---

## Configuration

Stored in UCI under `/etc/config/norypt`:

| Key | Default | Description |
|---|---|---|
| `enabled` | `1` | Master on/off switch |
| `randomize_imei` | `1` | Randomize modem IMEI on boot |
| `randomize_bssid` | `1` | Randomize Wi-Fi BSSIDs on boot |
| `randomize_wan` | `1` | Randomize WAN MAC on boot |
| `wipe_logs` | `1` | Wipe all logs on boot |
| `wipe_dhcp` | `1` | Wipe DHCP leases on boot |
| `on_boot` | `1` | Run automatically at boot |
| `settle_delay` | `3` | Seconds to wait after modem init |
| `cellular_timeout` | `60` | Seconds to wait for cellular IP |
| `log_history` | `10` | Boot events kept in panel history |

---

## How It Works

1. **IMEI** — picks a random TAC from `tac.db` (220 real phone TAC codes), appends 6 digits sourced
   from `/proc/sys/kernel/random/uuid`, computes the Luhn check digit, and pushes the result via
   `AT+EGMR=1,7,"<imei>"` (after unlocking with `AT+QCFG="IMEI/LOCK",0`). On GL-iNet, the AT command
   is routed through the `ubus AT` daemon to avoid serial-port contention; on vanilla OpenWrt it
   falls back to `send_at` or direct serial I/O. Verification reads `AT+CGSN` and retries up to 3 times.

2. **BSSID** — selects a random OUI from `oui-wifi.db` (48 wireless-chipset vendors), generates 3
   random NIC bytes, and clears the multicast (bit 0) and locally-administered (bit 1) bits in the
   first byte. Applied via `ip link set address`, committed to UCI, then `wifi down && wifi up`
   so `hostapd` re-broadcasts the new BSSID.

3. **WAN MAC** — same OUI approach using `oui-wan.db` (45 NIC/router vendors). Set on `eth0` and
   stored in `network.wan.macaddr`. The hotplug script `99-norypt-wan` re-applies the stored MAC
   on every `ifup wan` so daemons can't silently reset it.

4. **Log wipe** — removes files in `/var/log/`, `/tmp/log/`, dnsmasq leases, hostapd ctrl sockets,
   `/tmp/.uci/` deltas, then restarts `/etc/init.d/log` to flush the in-memory ring buffer.

5. **Boot order** — the procd init script registers at `START=19` (one before `network`), so
   randomization completes before any DHCP or cellular registration leaks the original identifiers.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     /etc/init.d/norypt (procd)                  │
│                  START=19  →  /etc/norypt/run.sh --boot         │
└──────────────────────┬──────────────────────────────────────────┘
                       │
       ┌───────────────┼───────────────┬─────────────────┐
       ▼               ▼               ▼                 ▼
  log-wipe.sh    imei-random.sh   mac-random.sh    wan-mac.sh
       │               │               │                 │
       │           tac.db         oui-wifi.db        oui-wan.db
       │               │               │                 │
       ▼               ▼               ▼                 ▼
  /var/log/* .   AT+EGMR=1,7,…   ip link + uci    ip link + uci
                                                         │
                                                         ▼
                                            /etc/hotplug.d/iface/
                                                  99-norypt-wan
                                       (re-applies MAC on every ifup)

       ▲                                                        ▲
       │                                                        │
   norypt CLI ────────► /etc/norypt/run.sh ◄──── norypt.cgi ◄── browser
   (/usr/bin/norypt)                            (/www/cgi-bin)   panel
```

### Dependencies

| Package | Purpose |
|---|---|
| `uqmi` | Read current IMEI via `--get-imei` (fallback path) |
| `bash` | Required by IMEI / MAC modules (associative I/O, AT escaping) |
| `coreutils-shuf` | Unbiased urandom-seeded random selection from OUI/TAC DBs |
| `fcgiwrap` | Required only on `nginx` GL-iNet firmware to serve the CGI |

Tools already shipped by stock OpenWrt/GL-iNet: `ip`, `uci`, `wifi`, `ifup`, `ifdown`, `ubus`, `logger`.

---

## Project Structure

```
norypt-privacy/
├── src/
│   ├── modules/
│   │   ├── run.sh             # Top-level boot orchestrator
│   │   ├── detect_fw.sh       # Auto-detect interfaces / UCI / modem port
│   │   ├── imei-random.sh     # Modem IMEI randomization (AT)
│   │   ├── mac-random.sh      # Wi-Fi BSSID randomization (2 G + 5 G)
│   │   ├── wan-mac.sh         # WAN MAC randomization
│   │   ├── log-wipe.sh        # Full log + lease wipe
│   │   ├── random_mac.sh      # MAC generator (sourced helper)
│   │   ├── luhn.sh            # Luhn check digit (sourced helper)
│   │   └── cellular.sh        # Cellular reconnect after rotation
│   ├── db/
│   │   ├── tac.db             # 220 phone TAC codes (real)
│   │   ├── oui-wifi.db        # 48 Wi-Fi chipset OUIs (real)
│   │   └── oui-wan.db         # 45 NIC / router OUIs (real)
│   ├── bin/norypt             # CLI tool (/usr/bin/norypt)
│   ├── cgi-bin/norypt.cgi     # Panel backend, CSRF-protected
│   ├── www/                   # Panel frontend (HTML / CSS / JS)
│   ├── init.d/norypt          # procd service (START=19)
│   ├── hotplug.d/99-norypt-wan# WAN MAC re-application hook
│   ├── uci-defaults/99-norypt # First-boot + sysupgrade hook
│   └── config/norypt          # UCI config defaults
├── offline/
│   ├── install-offline.sh     # Offline installer
│   └── deps/                  # Bundled .ipk dependencies
├── logo/                      # Brand assets
├── install.sh                 # One-line online installer
├── uninstall.sh               # Clean uninstaller
├── Makefile                   # OpenWrt SDK package definition
└── README.md
```

---

## Security Notes

- The panel is **LAN-only** — it is never exposed on WAN or the cellular interface.
- All write actions on the CGI require a **per-session CSRF token** (`X-Norypt-Token` header)
  matched against `/tmp/norypt_csrf_<session>`. The token file is created server-side, never
  exposed in the URL, and stored with `0600` permissions when possible.
- Config writes go through a strict **server-side allowlist** of UCI keys — `set_config`
  rejects any key not in the schema (no UCI injection / command injection).
- **No external connections** are made at runtime. All randomization is fully local; the OUI
  and TAC databases ship with the package.
- Randomized identifiers use **real, in-circulation OUI/TAC prefixes** so they don't trip
  spoofed-address heuristics on cell towers or upstream WAN equipment.

---

## Uninstall

```sh
wget -O - https://raw.githubusercontent.com/dartonverhovan-ctrl/norypt-privacy/main/uninstall.sh | sh
```

Or manually:

```sh
/etc/init.d/norypt stop && /etc/init.d/norypt disable
rm -rf /etc/norypt /www/norypt
rm -f  /etc/init.d/norypt /usr/bin/norypt /www/cgi-bin/norypt.cgi
rm -f  /etc/config/norypt /etc/uci-defaults/99-norypt
rm -f  /etc/hotplug.d/iface/99-norypt-wan
sed -i '/norypt/d' /etc/sysupgrade.conf
```

---

## Contributors

| | |
|---|---|
| **Darton Verhovan** | Author and maintainer — design, implementation, hardware bring-up on GL-XE3000 |

Issues, fixes, and platform ports are welcome — open a PR or an issue at
<https://github.com/dartonverhovan-ctrl/norypt-privacy>.

---

## License

MIT — see `LICENSE` for full text.

<div align="center">

<sub>NORYPT Privacy — part of the NORYPT toolkit. Open source, use responsibly.</sub>

</div>
