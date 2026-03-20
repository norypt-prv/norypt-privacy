#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/random_mac.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/detect_fw.sh"

WIFI_DB="${WIFI_DB:-${SCRIPT_DIR}/oui-wifi.db}"
# IF_WIFI_2G / IF_WIFI_5G now auto-detected by detect_fw.sh (ra0/wlan0/ath0)
IF_WIFI_2G="${IF_WIFI_2G:-wlan0}"
IF_WIFI_5G="${IF_WIFI_5G:-wlan1}"

_log() { logger -t norypt "mac: $*" 2>/dev/null || echo "norypt mac: $*" >&2; }

_apply_mac() {
  local iface="$1" mac="$2" uci_key="$3"
  ip link set dev "${iface}" down
  ip link set dev "${iface}" address "${mac}"
  ip link set dev "${iface}" up
  uci set "wireless.${uci_key}.macaddr=${mac}"
}

main() {
  local mac_2g mac_5g
  mac_2g=$(random_mac_from_db "${WIFI_DB}")
  mac_5g=$(random_mac_from_db "${WIFI_DB}")
  _apply_mac "${IF_WIFI_2G}" "${mac_2g}" "${UCI_WIFI_2G}"
  _apply_mac "${IF_WIFI_5G}" "${mac_5g}" "${UCI_WIFI_5G}"
  uci commit wireless
  # wifi reload is insufficient for MAC changes — must do full down/up
  # wifi down may return non-zero if interfaces are not yet up at boot
  wifi down || true
  wifi up
  _log "${IF_WIFI_2G}=${mac_2g} ${IF_WIFI_5G}=${mac_5g}"
}

main "$@"
