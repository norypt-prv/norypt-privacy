#!/usr/bin/env bash
set -euo pipefail

IF_WWAN="${IF_WWAN:-wwan0}"
CELLULAR_TIMEOUT="${CELLULAR_TIMEOUT:-60}"

_log() { logger -t norypt "cellular: $*" 2>/dev/null || echo "norypt cellular: $*" >&2; }

_wait_for_ip() {
  local elapsed=0
  while [[ "${elapsed}" -lt "${CELLULAR_TIMEOUT}" ]]; do
    if ip addr show "${IF_WWAN}" 2>/dev/null | grep -q 'inet '; then
      _log "IP assigned on ${IF_WWAN}"
      return 0
    fi
    sleep 1
    elapsed=$(( elapsed + 1 ))
  done
  _log "timeout waiting for IP on ${IF_WWAN} after ${CELLULAR_TIMEOUT}s"
  return 1
}

main() {
  _log "reconnecting cellular"
  # ifdown may return non-zero if interface is already down — tolerate it
  ifdown wwan 2>/dev/null || true
  if [[ -z "${NORYPT_TEST:-}" ]]; then sleep 2; fi
  ifup wwan
  if [[ -z "${NORYPT_TEST:-}" ]]; then
    _wait_for_ip || true
  fi
  _log "cellular reconnect complete"
}

main "$@"
