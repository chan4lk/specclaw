# shellcheck shell=bash
dk() {
  kc --request-timeout=10s "$@" </dev/null 2>"$FLEET_TMPDIR/dk.err"
}

absent() {
  grep -q NotFound "$FLEET_TMPDIR/dk.err" && return 0
  echo "skip $1: could not ask the cluster: $(head -n1 "$FLEET_TMPDIR/dk.err")"; return 1
}

check_context() {
  local v
  v="$(dk version -o json | jq -r '.serverVersion.gitVersion // empty')"
  [[ -n "$v" ]] || { echo "missing context: cannot reach the cluster${FLEET_KUBE_CONTEXT:+ ($FLEET_KUBE_CONTEXT)}"; return 1; }
  echo "ok context: ${FLEET_KUBE_CONTEXT:-current} $v"
}

check_namespaces() {
  dk get ns "$D_NS" specclaw-fleet-egress -o name >/dev/null && { echo "ok namespaces: $D_NS, specclaw-fleet-egress"; return 0; }
  absent namespaces || return 2
  echo "missing namespaces: apply plugins/specclaw-fleet/k8s/"; return 1
}

check_rbac() {
  dk -n "$D_NS" get serviceaccount/fleet-dispatcher role/fleet-dispatcher rolebinding/fleet-dispatcher -o name >/dev/null \
    && { echo "ok rbac: fleet-dispatcher"; return 0; }
  absent rbac || return 2
  echo "missing rbac: apply plugins/specclaw-fleet/k8s/rbac.yaml"; return 1
}

check_egress() {
  local ready
  if ! ready="$(dk -n specclaw-fleet-egress get deploy fleet-egress -o jsonpath='{.status.readyReplicas}')"; then
    absent egress || return 2
    echo "missing egress: apply plugins/specclaw-fleet/k8s/egress-proxy.yaml"; return 1
  fi
  (( ${ready:-0} >= 1 )) && { echo "ok egress: proxy ready ($ready)"; return 0; }
  echo "wrong egress: fleet-egress proxy not ready"; return 1
}

check_netpol() {
  dk -n "$D_NS" get networkpolicy fleet-pods -o name >/dev/null && { echo "ok netpol: fleet-pods"; return 0; }
  absent netpol || return 2
  echo "missing netpol: apply plugins/specclaw-fleet/k8s/network-policy.yaml"; return 1
}

check_secret() {
  local name="$1" keys json have
  shift
  if ! json="$(dk -n "$D_NS" get secret "$name" -o json)"; then
    absent "secret:$name" || return 2
    echo "missing secret:$name"; return 1
  fi
  have="$(jq -r '.data // {} | keys | join(" ")' <<<"$json")"
  for keys in "$@"; do
    [[ " $have " == *" $keys "* ]] || { echo "wrong secret:$name: lacks key $keys"; return 1; }
  done
  echo "ok secret:$name: $*"
}
