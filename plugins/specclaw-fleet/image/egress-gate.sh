# shellcheck shell=bash
egress_ready() {
  curl -s -o /dev/null -m 3 -x "$HTTPS_PROXY" https://dev.azure.com/ || return 1
  ! curl -s -o /dev/null -m 3 --noproxy '*' https://dev.azure.com/
}

wait_for_egress() {
  local try
  for ((try = 1; try <= ${FLEET_GATE_TRIES:-30}; try++)); do
    egress_ready && return 0
    sleep "${FLEET_GATE_SLEEP:-2}"
  done
  return 1
}
