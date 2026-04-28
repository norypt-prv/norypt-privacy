#!/usr/bin/env bash
# imei-random.sh — region- and brand-aware IMEI randomization.
#
# Pulls TACs from a curated database (src/db/tac.db), selects one
# matching the SIM's region (derived from IMSI MCC) and the
# user-configured brand, generates a non-degenerate 6-digit serial,
# computes the Luhn check digit, and writes the IMEI to the modem
# via AT+EGMR=1,7,"<imei>".
#
# Config keys read from /etc/config/norypt.settings:
#   imei_brand           apple | samsung | xiaomi | motorola | all   (default: all)
#   imei_region          eu | na | asia | latam | global | auto      (default: auto)
#   imei_default_region  fallback when MCC unknown                   (default: eu)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/luhn.sh"

TAC_DB="${TAC_DB:-${SCRIPT_DIR}/tac.db}"
MODEM_PORT="${MODEM_PORT:-}"
AT_RETRIES=3
MODEM_WAIT=15

_log() { logger -t norypt "imei: $*" 2>/dev/null || echo "norypt imei: $*" >&2; }

_cfg() { uci -q get "norypt.settings.$1" 2>/dev/null || echo ""; }

_wait_for_modem() {
  [[ -n "${NORYPT_TEST:-}" ]] && return 0
  ubus list AT >/dev/null 2>&1 && return 0
  for _ in $(seq 1 "${MODEM_WAIT}"); do
    [[ -e "${MODEM_PORT}" ]] && return 0
    sleep 1
  done
  _log "modem not accessible after ${MODEM_WAIT}s — skipping IMEI"
  return 1
}

# Send an AT command. Returns the modem reply on stdout.
_at() {
  local cmd="$1"
  if command -v send_at >/dev/null 2>&1; then
    send_at "${MODEM_PORT}" "${cmd}"
  elif ubus list AT >/dev/null 2>&1; then
    local escaped="${cmd//\"/\\\"}"
    ubus call AT get_result "{\"cmd\":\"AT${escaped}\",\"timeout\":5000}" 2>/dev/null
  else
    stty -F "${MODEM_PORT}" 115200 raw -echo 2>/dev/null || true
    exec 3<>"${MODEM_PORT}"
    timeout 1 head -c 512 <&3 2>/dev/null || true
    printf 'AT%s\r' "${cmd}" >&3
    sleep 0.4
    timeout 1 head -c 256 <&3 2>/dev/null || true
    exec 3>&-
  fi
}

# Read IMSI from the SIM (works in flight mode — no radio attach needed).
_read_imsi() {
  [[ -n "${MOCK_IMSI:-}" ]] && { echo "${MOCK_IMSI}"; return 0; }
  _at '+CIMI' 2>/dev/null | grep -oE '[0-9]{15}' | head -1
}

# MCC -> region. Mirrors mcc_to_region() in the upstream Python source.
# Empty output = MCC unknown / unmapped (caller falls back).
_mcc_to_region() {
  local mcc="$1"
  [[ "${mcc}" =~ ^[0-9]{3}$ ]] || return 0
  local n=$(( 10#${mcc} ))
  if (( n >= 200 && n <= 299 )); then echo "eu"; return; fi
  case "${n}" in
    302|308|334) echo "na"; return ;;
    310|311|312|313|314|315|316) echo "na"; return ;;
    338|340|342|344|346|348|350|352|354|356|358|360|362|363|364|365|366|368|370|372|374|376)
      echo "na"; return ;;
    706|708|710|712|714|716|722|724|725|730|732|734|736|738|740|744|746|748)
      echo "latam"; return ;;
  esac
  if (( n >= 400 && n <= 599 )); then echo "asia"; return; fi
  # Unknown MCC — caller uses default_region
}

# Filter the TAC database by brand + region. Always unions with 'global'
# so every brand has a non-empty pool even in regions with no specific
# launches.
_tac_pool() {
  local brand="$1" region="$2"
  awk -v B="${brand}" -v R="${region}" '
    /^#|^$/ { next }
    NF < 3 { next }
    {
      tac=$1; b=$2; r=$3
      if (B != "all" && b != B) next
      if (r == R || r == "global") print tac
    }
  ' "${TAC_DB}"
}

# Reject degenerate 6-digit serials (all-zero / repeating, strict
# ascending or descending, palindromes). Operator fraud heuristics
# flag these regardless of CEIR status.
_is_degenerate_serial() {
  local s="$1" i prev cur asc=1 desc=1
  # all same digit
  if [[ "${s}" =~ ^(.)\1{5}$ ]]; then return 0; fi
  # palindrome
  local rev="" len=${#s}
  for (( i=len-1; i>=0; i-- )); do rev+="${s:${i}:1}"; done
  [[ "${s}" = "${rev}" ]] && return 0
  # strict +1 / -1 runs
  prev="${s:0:1}"
  for (( i=1; i<len; i++ )); do
    cur="${s:${i}:1}"
    (( cur == prev + 1 )) || asc=0
    (( cur == prev - 1 )) || desc=0
    prev="${cur}"
  done
  (( asc || desc )) && return 0
  return 1
}

_random_serial() {
  # /proc/sys/kernel/random/uuid yields 32 hex chars; tr to digits and
  # take 6. If we run out, loop until we get 6 digits.
  local digits=""
  while [[ ${#digits} -lt 6 ]]; do
    digits+="$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -dc '0-9')"
  done
  echo "${digits:0:6}"
}

_pick_tac() {
  local pool="$1" count
  count=$(echo "${pool}" | wc -l)
  echo "${pool}" | shuf -n1
}

_resolve_region() {
  local cfg_region cfg_default imsi mcc derived
  cfg_region=$(_cfg imei_region)
  cfg_default=$(_cfg imei_default_region)
  [[ -z "${cfg_default}" ]] && cfg_default="eu"

  if [[ -n "${cfg_region}" ]] && [[ "${cfg_region}" != "auto" ]]; then
    echo "${cfg_region}"; return
  fi

  imsi=$(_read_imsi)
  if [[ -n "${imsi}" ]] && [[ ${#imsi} -ge 6 ]]; then
    mcc="${imsi:0:3}"
    derived=$(_mcc_to_region "${mcc}")
    if [[ -n "${derived}" ]]; then
      _log "region=${derived} (from IMSI MCC ${mcc})"
      echo "${derived}"; return
    fi
    _log "region=${cfg_default} (MCC ${mcc} unmapped)"
  else
    _log "region=${cfg_default} (no IMSI)"
  fi
  echo "${cfg_default}"
}

_resolve_brand() {
  local cfg_brand
  cfg_brand=$(_cfg imei_brand)
  case "${cfg_brand}" in
    apple|samsung|xiaomi|motorola) echo "${cfg_brand}" ;;
    *) echo "all" ;;
  esac
}

_generate_imei() {
  local brand region pool tac serial check imei
  brand=$(_resolve_brand)
  region=$(_resolve_region)
  pool=$(_tac_pool "${brand}" "${region}")
  if [[ -z "${pool}" ]]; then
    # Region had no TACs even after global merge — should not happen
    # given _validate_database equivalent, but guard anyway.
    _log "no TACs for brand=${brand} region=${region} — falling back to all/global"
    pool=$(_tac_pool "all" "global")
  fi
  tac=$(_pick_tac "${pool}")
  local attempt
  for (( attempt=0; attempt<64; attempt++ )); do
    serial=$(_random_serial)
    _is_degenerate_serial "${serial}" || break
  done
  check=$(luhn_digit "${tac}${serial}")
  imei="${tac}${serial}${check}"
  _log "selected brand=${brand} region=${region} tac=${tac}"
  echo "${imei}"
}

main() {
  local new_imei
  new_imei=$(_generate_imei)

  if [[ -n "${NORYPT_TEST:-}" ]]; then
    echo "${new_imei}"
    return 0
  fi

  if ! _wait_for_modem; then return 1; fi

  _at '+QCFG="IMEI/LOCK",0' >/dev/null

  local attempt=0 verified
  while [[ "${attempt}" -lt "${AT_RETRIES}" ]]; do
    _at "+EGMR=1,7,\"${new_imei}\"" >/dev/null
    verified=$(_at '+CGSN' | grep -oE '[0-9]{15}' | head -1)
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
