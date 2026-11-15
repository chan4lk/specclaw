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
  [[ -n "$v" ]] && { echo "ok context: ${FLEET_KUBE_CONTEXT:-current} $v"; return 0; }
  grep -Eqi 'context .*(not found|does not exist)|current-context is not set' "$FLEET_TMPDIR/dk.err" \
    && { echo "missing context: ${FLEET_KUBE_CONTEXT:-current} is not in the kubeconfig"; return 1; }
  echo "skip context: could not ask the cluster: $(head -n1 "$FLEET_TMPDIR/dk.err")"; return 2
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

check_bundles() {
  local c="${FLEET_BUNDLE_CLAIM:-}" state nodes n
  [[ -n "$c" ]] || { echo "ok bundles: off"; return 0; }
  if ! state="$(dk -n "$D_NS" get pvc "$c" -o jsonpath='{.status.phase} {.metadata.annotations.volume\.kubernetes\.io/selected-node}')"; then
    absent bundles || return 2
    echo "missing bundles: claim $c not found; apply plugins/specclaw-fleet/k8s/bundles-pvc.yaml"; return 1
  fi
  # A WaitForFirstConsumer class (k3s local-path) leaves the claim Pending, with no selected node, until a pod mounts it.
  [[ "$state" == Bound* || "$state" == "Pending " ]] \
    || { echo "missing bundles: claim $c is ${state%% *}, not Bound; check its events, or re-apply plugins/specclaw-fleet/k8s/bundles-pvc.yaml"; return 1; }
  # With node_label set, exactly one node may match it: the claim lives on one node.
  nodes="$(dk get nodes ${FLEET_NODE_LABEL:+-l "$FLEET_NODE_LABEL"} -o name)" \
    || { echo "skip bundles: could not list nodes: $(head -n1 "$FLEET_TMPDIR/dk.err")"; return 2; }
  n="$(grep -c . <<<"$nodes")"
  [[ -z "${FLEET_NODE_LABEL:-}" ]] || (( n == 1 )) \
    || { echo "missing bundles: fleet.node_label $FLEET_NODE_LABEL matches $n nodes; label exactly one node so every Job lands where $c lives"; return 1; }
  [[ -n "${FLEET_NODE_LABEL:-}" ]] || (( n <= 1 )) \
    || { echo "missing bundles: the cluster has several nodes; set fleet.node_label so every Job lands where $c lives"; return 1; }
  [[ "$state" == Bound* ]] && echo "ok bundles: $c" || echo "ok bundles: $c (binds on first use)"
}
