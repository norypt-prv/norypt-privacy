#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/luhn.sh"

TAC_DB="${TAC_DB:-${SCRIPT_DIR}/tac.db}"
MODEM_PORT="${MODEM_PORT:-}"
AT_RETRIES=3
MODEM_WAIT=15

_log() { logger -t norypt "imei: $*" 2>/dev/null || echo "norypt imei: $*" >&2; }

_wait_for_modem() {
  [[ -n "${NORYPT_TEST:-}" ]] && return 0
  # GL-iNet ubus AT daemon: modem accessible without holding the physical port
  ubus list AT >/dev/null 2>&1 && return 0
  for _ in $(seq 1 "${MODEM_WAIT}"); do
    [[ -e "${MODEM_PORT}" ]] && return 0
    sleep 1
  done
  _log "modem not accessible after ${MODEM_WAIT}s — skipping IMEI"
  return 1
}

_at() {
  local cmd="$1"
  # send_at handles the serial I/O when on PATH (mocks in test, real binary in prod)
  if command -v send_at >/dev/null 2>&1; then
    send_at "${MODEM_PORT}" "${cmd}"
  elif ubus list AT >/dev/null 2>&1; then
    # GL-iNet firmware: route through modem_AT ubus daemon to avoid port contention
    # Escape inner quotes so cmd with "quoted args" produces valid JSON
    local escaped="${cmd//\"/\\\"}"
    ubus call AT get_result "{\"cmd\":\"AT${escaped}\",\"timeout\":5000}" 2>/dev/null
  else
    # Fallback: direct serial (vanilla OpenWrt without modem_AT daemon)
    stty -F "${MODEM_PORT}" 115200 raw -echo 2>/dev/null || true
    local response
    exec 3<>"${MODEM_PORT}"
    timeout 1 head -c 512 <&3 2>/dev/null || true
    printf 'AT%s\r' "${cmd}" >&3
    sleep 0.4
    response=$(timeout 1 head -c 256 <&3 2>/dev/null || true)
    exec 3>&-
    echo "${response}"
  fi
}

_generate_imei() {
  # shuf provides unbiased urandom-seeded line selection (coreutils-shuf dep)
  local tac
  tac=$(shuf -n1 "${TAC_DB}")
  local serial
  serial=$(cat /proc/sys/kernel/random/uuid | tr -dc '0-9' | head -c 6)
  local prefix="${tac}${serial}"
  local check
  check=$(luhn_digit "${prefix}")
  echo "${prefix}${check}"
}

main() {
  local new_imei
  new_imei=$(_generate_imei)

  if [[ -n "${NORYPT_TEST:-}" ]]; then
    echo "${new_imei}"
    return 0
  fi

  _wait_for_modem
  local modem_ok=$?
  if [[ "${modem_ok}" -ne 0 ]]; then return 1; fi

  _at '+QCFG="IMEI/LOCK",0' >/dev/null

  local attempt=0
  while [[ "${attempt}" -lt "${AT_RETRIES}" ]]; do
    _at "+EGMR=1,7,\"${new_imei}\"" >/dev/null
    local verified
    verified=$(_at "+CGSN" | grep -oE '[0-9]{15}' | head -1)
    if [[ "${verified}" = "${new_imei}" ]]; then
      _log "IMEI set to ${new_imei}"
      echo "${new_imei}"
      return 0
    fi
    attempt=$(( attempt + 1 ))
    sleep 1
  done

  _log "IMEI verification failed after ${AT_RETRIES} attempts"
  return 1
}

main "$@"
