#!/usr/bin/env bash
set -euo pipefail

MODULES_DIR="${NORYPT_MODULES_DIR:-/etc/norypt}"
HISTORY_FILE="${NORYPT_HISTORY_FILE:-${MODULES_DIR}/history.log}"
WWW_DIR="${NORYPT_WWW_DIR:-/www/norypt}"

_header() { printf 'Content-Type: text/plain\r\n\r\n'; }

_403() {
  printf 'Status: 403 Forbidden\r\nContent-Type: text/plain\r\n\r\nForbidden\n'
  exit 0
}

_session_key() {
  # Prefer GL-iNet sysauth cookie; fall back to REMOTE_ADDR so unauthenticated
  # LAN clients still get a per-client (not shared) token file.
  local sid
  sid=$(echo "${HTTP_COOKIE:-}" | grep -oE 'sysauth=[^;]+' | cut -d= -f2 | tr -dc 'a-zA-Z0-9' || true)
  [[ -z "${sid}" ]] && sid=$(echo "${REMOTE_ADDR:-anon}" | tr -dc 'a-zA-Z0-9.:_-')
  echo "${sid:-anon}"
}

_check_csrf() {
  local provided="${HTTP_X_NORYPT_TOKEN:-}"
  if [[ -n "${NORYPT_TEST:-}" ]]; then
    [[ "${provided}" = "${NORYPT_CSRF_TOKEN:-}" ]] || _403
    return
  fi
  local token_file="/tmp/norypt_csrf_$(_session_key)"
  local stored=""
  [[ -f "${token_file}" ]] && stored=$(cat "${token_file}")
  if [[ -n "${stored}" ]] && [[ "${provided}" = "${stored}" ]]; then
    return
  fi
  _403
}

_kv_status() {
  # shellcheck source=/dev/null
  source "${MODULES_DIR}/detect_fw.sh" 2>/dev/null || true
  local imei bssid_2g bssid_5g wan_mac cellular
  # Use GL-iNet ubus AT daemon (avoids port contention; works with PCIe MHI modems)
  imei=$(ubus call AT get_result '{"cmd":"AT+EGMR=0,7","timeout":3000}' 2>/dev/null \
    | grep -oE '[0-9]{15}' | head -1 || echo "unavailable")
  bssid_2g=$(ip link show "${IF_WIFI_2G:-wlan0}" 2>/dev/null | awk '/ether/{print $2}' || echo "unavailable")
  bssid_5g=$(ip link show "${IF_WIFI_5G:-wlan1}" 2>/dev/null | awk '/ether/{print $2}' || echo "unavailable")
  wan_mac=$(ip link show "${IF_WAN:-eth0}"       2>/dev/null | awk '/ether/{print $2}' || echo "unavailable")
  if ip addr show "${IF_WWAN:-wwan0}" 2>/dev/null | grep -q 'inet '; then
    cellular="connected"
  else
    cellular="disconnected"
  fi
  printf 'imei=%s\nbssid_2g=%s\nbssid_5g=%s\nwan_mac=%s\ncellular=%s\nfw=%s\n' \
    "${imei}" "${bssid_2g}" "${bssid_5g}" "${wan_mac}" "${cellular}" "${FW_VERSION:-unknown}"
}

_log_event() {
  # shellcheck disable=SC2312
  printf '%s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "${2:-}" >> "${HISTORY_FILE}"
  # Guard: only rotate if file is non-empty to avoid writing a blank line on first call
  if [[ -s "${HISTORY_FILE}" ]]; then
    local tmp; tmp=$(tail -100 "${HISTORY_FILE}"); printf '%s\n' "${tmp}" > "${HISTORY_FILE}"
  fi
}

_serve_index() {
  local token_file token html
  token_file="/tmp/norypt_csrf_$(_session_key)"
  if [[ ! -f "${token_file}" ]]; then
    token=$(cat /proc/sys/kernel/random/uuid | tr -d '-')
    printf '%s' "${token}" > "${token_file}"
    chmod 600 "${token_file}" 2>/dev/null || true
  else
    token=$(cat "${token_file}")
  fi
  html=$(sed "s/__CSRF_TOKEN__/${token}/g" "${WWW_DIR}/index.html")
  printf 'Content-Type: text/html\r\n\r\n'
  printf '%s\n' "${html}"
}

_run_action() {
  # QUERY_STRING is set by the CGI environment at runtime
  # shellcheck disable=SC2154
  local action="${QUERY_STRING#action=}"
  action="${action%%&*}"

  # serve_index does not require CSRF — it sets the token
  if [[ "${action}" = "serve_index" ]]; then _serve_index; return; fi

  _check_csrf

  case "${action}" in
    status)
      _header; _kv_status ;;
    randomize)
      _header; bash "${MODULES_DIR}/run.sh" 2>&1; _log_event "randomize" "all" ;;
    randomize_imei)
      _header; bash "${MODULES_DIR}/imei-random.sh" 2>&1; _log_event "randomize" "imei" ;;
    randomize_mac)
      _header; bash "${MODULES_DIR}/mac-random.sh" 2>&1; _log_event "randomize" "bssid" ;;
    randomize_wan)
      _header; bash "${MODULES_DIR}/wan-mac.sh" 2>&1; _log_event "randomize" "wan" ;;
    wipe_logs)
      _header; bash "${MODULES_DIR}/log-wipe.sh" 2>&1; _log_event "wipe_logs" "" ;;
    set_config)
      _header
      local body=""
      read -r -N "${CONTENT_LENGTH:-0}" body 2>/dev/null || true
      local key val
      key="${body%%=*}"; val="${body##*=}"
      # Whitelist key names to prevent UCI injection / command injection
      case "${key}" in
        enabled|randomize_imei|randomize_bssid|randomize_wan|\
        wipe_logs|wipe_dhcp|on_boot|settle_delay|\
        cellular_timeout|log_history|\
        imei_brand|imei_region|imei_default_region) ;;
        *) printf 'error=invalid_key\n'; return ;;
      esac
      # Validate string-valued keys to a small allowlist (rest are numeric).
      case "${key}" in
        imei_brand)
          case "${val}" in apple|samsung|xiaomi|motorola|all) ;;
            *) printf 'error=invalid_value\n'; return ;; esac ;;
        imei_region)
          case "${val}" in auto|eu|na|asia|latam|global) ;;
            *) printf 'error=invalid_value\n'; return ;; esac ;;
        imei_default_region)
          case "${val}" in eu|na|asia|latam|global) ;;
            *) printf 'error=invalid_value\n'; return ;; esac ;;
      esac
      uci set "norypt.settings.${key}=${val}" && uci commit norypt
      printf 'ok=%s\n' "${key}"
      ;;
    get_history)
      _header
      if [[ -f "${HISTORY_FILE}" ]]; then tail -10 "${HISTORY_FILE}"
      else printf 'no_history=1\n'; fi
      ;;
    get_config)
      _header
      for k in enabled randomize_imei randomize_bssid randomize_wan \
               wipe_logs wipe_dhcp on_boot settle_delay \
               cellular_timeout log_history \
               imei_brand imei_region imei_default_region; do
        printf '%s=%s\n' "${k}" "$(uci -q get norypt.settings.${k} 2>/dev/null || echo '')"
      done
      ;;
    *)
      printf 'Status: 400 Bad Request\r\nContent-Type: text/plain\r\n\r\nUnknown action\n'
      ;;
  esac
}

_run_action
