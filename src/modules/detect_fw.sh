#!/usr/bin/env bash
# detect_fw.sh — source this file to populate FW_VERSION, MODEM_PORT,
# IF_WAN, IF_WIFI_2G, IF_WIFI_5G, IF_WWAN, IF_CDC
#
# Accepts MOCK_RELEASE and MOCK_GLVERSION env vars for testing.

_glver="${MOCK_GLVERSION:-$(cat /etc/glversion 2>/dev/null)}"

if [[ -n "${_glver}" ]]; then
  _major=$(echo "${_glver}" | cut -d. -f1)
  _minor=$(echo "${_glver}" | cut -d. -f2)
  if [[ "${_major}" -ge 4 ]] && [[ "${_minor}" -ge 5 ]]; then
    FW_VERSION="v4.5+"
  else
    FW_VERSION="v4"
  fi
else
  FW_VERSION="vanilla"
fi

IF_WAN="${IF_WAN_OVERRIDE:-eth0}"
IF_WWAN="${IF_WWAN_OVERRIDE:-wwan0}"
IF_CDC="${IF_CDC_OVERRIDE:-/dev/cdc-wdm0}"

_resolve_wifi_2g() {
  # MediaTek (GL-XE3000, MT7981): ra0  |  Qualcomm/ath9k: wlan0
  for iface in ra0 wlan0 ath0; do
    ip link show "${iface}" >/dev/null 2>&1 && echo "${iface}" && return
  done
  echo "wlan0"
}

_resolve_wifi_5g() {
  # MediaTek 5 GHz: rax0  |  Qualcomm/ath9k: wlan1
  for iface in rax0 wlan1 ath1; do
    ip link show "${iface}" >/dev/null 2>&1 && echo "${iface}" && return
  done
  echo "wlan1"
}

IF_WIFI_2G="${IF_WIFI_2G_OVERRIDE:-$(_resolve_wifi_2g)}"
IF_WIFI_5G="${IF_WIFI_5G_OVERRIDE:-$(_resolve_wifi_5g)}"

_resolve_modem_port() {
  # PCIe MHI modem (GL-XE3000 built-in Quectel EM060K) exposes AT via mhi_DUN
  for port in /dev/mhi_DUN /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB0 /dev/ttyUSB3; do
    [[ -e "${port}" ]] && echo "${port}" && return
  done
  echo ""
}
MODEM_PORT="${MODEM_PORT_OVERRIDE:-$(_resolve_modem_port)}"

export FW_VERSION IF_WAN IF_WIFI_2G IF_WIFI_5G IF_WWAN IF_CDC MODEM_PORT
