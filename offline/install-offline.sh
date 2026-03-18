#!/bin/sh
# NORYPT Privacy — Offline Installer
# Usage: sh install-offline.sh  (run on the router via SSH after copying this folder)
# Requires: this script and the deps/ folder to be in the same directory
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPS_DIR="${SCRIPT_DIR}/deps"

MODULES=/etc/norypt
WWW=/www/norypt
CGI=/www/cgi-bin

echo "=== NORYPT Privacy Offline Installer v1.0.0 ==="

if [ -f /etc/glversion ]; then
  echo "Detected GL-iNet firmware v$(cat /etc/glversion)"
else
  echo "Detected vanilla OpenWrt"
fi

# ── 1. Install bundled dependencies ─────────────────────────────────────────

echo ""
echo "[1/5] Installing dependencies from bundled .ipk files..."

if [ ! -d "${DEPS_DIR}" ]; then
  echo "ERROR: deps/ folder not found at ${DEPS_DIR}"
  echo "Make sure the deps/ folder is in the same directory as this script."
  exit 1
fi

for ipk in \
  libubox20230523_*.ipk \
  libblobmsg-json20230523_*.ipk \
  libncurses6_*.ipk \
  libreadline8_*.ipk \
  wwan_*.ipk \
  coreutils_*.ipk \
  coreutils-shuf_*.ipk \
  bash_*.ipk \
  uqmi_*.ipk; do

  filepath="${DEPS_DIR}/${ipk}"
  # expand glob — skip if no match
  [ -f "${filepath}" ] || { echo "  WARNING: ${ipk} not found in deps/ — skipping"; continue; }

  pkgname=$(echo "${ipk}" | cut -d_ -f1)
  if opkg list-installed 2>/dev/null | grep -q "^${pkgname} "; then
    echo "  already installed: ${pkgname}"
  else
    echo "  installing: ${pkgname}"
    opkg install --force-reinstall "${filepath}" || echo "  WARNING: failed to install ${pkgname}"
  fi
done

# ── 2. Install NORYPT modules and databases ──────────────────────────────────

echo ""
echo "[2/5] Installing NORYPT modules..."

mkdir -p "${MODULES}" "${WWW}" "${CGI}"

SRC="${SCRIPT_DIR}/src"

if [ ! -d "${SRC}" ]; then
  echo "ERROR: src/ folder not found at ${SRC}"
  echo "Make sure you copied the full norypt-privacy folder, not just offline/."
  exit 1
fi

for f in detect_fw.sh luhn.sh random_mac.sh imei-random.sh \
          mac-random.sh wan-mac.sh log-wipe.sh cellular.sh run.sh; do
  echo "  ${MODULES}/${f}"
  cp "${SRC}/modules/${f}" "${MODULES}/${f}"
  chmod 755 "${MODULES}/${f}"
done

for f in tac.db oui-wifi.db oui-wan.db; do
  echo "  ${MODULES}/${f}"
  cp "${SRC}/db/${f}" "${MODULES}/${f}"
  chmod 644 "${MODULES}/${f}"
done

# ── 3. Install service files ─────────────────────────────────────────────────

echo ""
echo "[3/5] Installing service files..."

cp "${SRC}/init.d/norypt"         /etc/init.d/norypt          && chmod 755 /etc/init.d/norypt
cp "${SRC}/uci-defaults/99-norypt" /etc/uci-defaults/99-norypt && chmod 755 /etc/uci-defaults/99-norypt
cp "${SRC}/bin/norypt"            /usr/bin/norypt              && chmod 755 /usr/bin/norypt
cp "${SRC}/cgi-bin/norypt.cgi"   "${CGI}/norypt.cgi"          && chmod 755 "${CGI}/norypt.cgi"

if [ ! -f /etc/config/norypt ]; then
  cp "${SRC}/config/norypt" /etc/config/norypt && chmod 644 /etc/config/norypt
fi

# ── 4. Install web panel ─────────────────────────────────────────────────────

echo ""
echo "[4/5] Installing web panel..."

for f in index.html style.css app.js; do
  echo "  ${WWW}/${f}"
  cp "${SRC}/www/${f}" "${WWW}/${f}"
  chmod 644 "${WWW}/${f}"
done

# ── 5. Enable service + uhttpd redirect + sysupgrade ─────────────────────────

echo ""
echo "[5/5] Enabling service and configuring router..."

/etc/init.d/norypt enable
/etc/init.d/norypt start

if uci show uhttpd >/dev/null 2>&1; then
  if ! uci show uhttpd 2>/dev/null | grep -q "norypt_redirect"; then
    uci add uhttpd redirect > /dev/null
    uci set uhttpd.@redirect[-1].name='norypt_redirect'
    uci set uhttpd.@redirect[-1].from='/norypt/'
    uci set uhttpd.@redirect[-1].to='/cgi-bin/norypt.cgi?action=serve_index'
    uci commit uhttpd
  fi
  /etc/init.d/uhttpd restart 2>/dev/null || true
fi

if ! grep -q '/etc/norypt/' /etc/sysupgrade.conf 2>/dev/null; then
  cat >> /etc/sysupgrade.conf << 'EOF'
/etc/norypt/
/etc/config/norypt
/etc/init.d/norypt
/etc/uci-defaults/99-norypt
/usr/bin/norypt
/www/cgi-bin/norypt.cgi
/www/norypt/
EOF
fi

echo ""
echo "=== Done ==="
echo "Panel : http://192.168.8.1/norypt/"
echo "CLI   : norypt status"
