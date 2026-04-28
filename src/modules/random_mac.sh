#!/usr/bin/env bash
# random_mac.sh — MAC address generation from OUI database
# Source this file to use random_mac_from_db()
# Requires: shuf (coreutils-shuf)

random_mac_from_db() {
  local db="$1"
  # shuf provides unbiased urandom-seeded line selection (coreutils-shuf dep)
  local oui
  # shellcheck disable=SC2312
  oui=$(shuf -n1 "${db}" | awk '{print $1}')
  # Generate 3 random NIC bytes from /proc/sys/kernel/random/uuid (no od/SIGPIPE)
  local _raw _b1 _b2 _b3 nic
  _raw=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
  _b1="${_raw:0:2}"; _b2="${_raw:2:2}"; _b3="${_raw:4:2}"
  nic=$(printf '%s:%s:%s' "${_b1}" "${_b2}" "${_b3}" | tr 'a-f' 'A-F')
  # Ensure bit0=0 (unicast) and bit1=0 (globally unique) in first byte
  local first val
  first=$(echo "${oui}" | cut -d: -f1)
  val=$(( 16#${first} & 0xFC ))
  first=$(printf "%02X" "${val}")
  oui="${first}:$(echo "${oui}" | cut -d: -f2-3)"
  echo "${oui}:${nic}"
}
