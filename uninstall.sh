#!/bin/sh
set -e
echo "=== NORYPT Privacy Uninstaller ==="

echo "Stopping service..."
/etc/init.d/norypt stop    2>/dev/null || true
/etc/init.d/norypt disable 2>/dev/null || true

echo "Removing files..."
rm -rf /etc/norypt /www/norypt
rm -f  /etc/init.d/norypt /usr/bin/norypt /www/cgi-bin/norypt.cgi
rm -f  /etc/config/norypt /etc/uci-defaults/99-norypt

echo "Removing web server config..."
# uhttpd redirect
_norypt_sec=$(uci show uhttpd 2>/dev/null | grep "\.name='norypt_redirect'" | cut -d. -f1-2)
if [ -n "${_norypt_sec}" ]; then
  uci delete "${_norypt_sec}"
  uci commit uhttpd
  /etc/init.d/uhttpd restart 2>/dev/null || true
fi
# nginx GL-iNet (gl-conf.d)
if [ -f /etc/nginx/gl-conf.d/norypt.conf ]; then
  rm -f /etc/nginx/gl-conf.d/norypt.conf
  nginx -t && nginx -s reload 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true
fi
# nginx fallback (conf.d)
if [ -f /etc/nginx/conf.d/norypt.conf ]; then
  rm -f /etc/nginx/conf.d/norypt.conf
  nginx -t && nginx -s reload 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true
fi

echo "Cleaning sysupgrade list..."
if [ -f /etc/sysupgrade.conf ]; then
  sed -i '/norypt/d' /etc/sysupgrade.conf
fi

echo ""
echo "=== Done — NORYPT Privacy removed ==="
