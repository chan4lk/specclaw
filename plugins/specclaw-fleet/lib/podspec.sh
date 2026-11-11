# shellcheck shell=bash disable=SC2034
parse_pod_inputs() {
  F_CLAUDE_VERSION="${FLEET_CLAUDE_VERSION:-}"
  if [[ "$F_AGENT" == claude || -n "$F_CLAUDE_VERSION" ]]; then
    [[ "$F_CLAUDE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "FLEET_CLAUDE_VERSION must be a release like 2.1.319 (required for claude jobs)"
  fi
  F_PULL_SECRET="${FLEET_IMAGE_PULL_SECRET:-}"
  [[ -z "$F_PULL_SECRET" || "$F_PULL_SECRET" =~ ^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$ ]] \
    || die "FLEET_IMAGE_PULL_SECRET is not a valid secret name"
  F_MODE="${FLEET_MODE:-}" F_MERGE_REF="${FLEET_MERGE_REF:-}" F_PR_TARGET="${FLEET_PR_TARGET:-}"
  [[ -z "$F_MODE" || "$F_MODE" == integrate ]] || die "FLEET_MODE must be empty or integrate"
  local r; for r in "$F_MERGE_REF" "$F_PR_TARGET"; do
    [[ -z "$r" || ( "$r" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ && "$r" != *..* ) ]] || die "'$r' is not a valid branch name"
  done
  parse_postgres
  F_NODE_KEY="" F_NODE_VALUE=""
  if [[ -n "${FLEET_NODE_LABEL:-}" ]]; then
    [[ "$FLEET_NODE_LABEL" =~ ^([a-z0-9.-]+/)?[A-Za-z0-9][-A-Za-z0-9_.]{0,62}=[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$ ]] \
      || die "FLEET_NODE_LABEL must be key=value"
    F_NODE_KEY="${FLEET_NODE_LABEL%%=*}" F_NODE_VALUE="${FLEET_NODE_LABEL#*=}"
  fi
}

render_pod_extras() {
  [[ -n "$F_PULL_SECRET" ]] && printf '      imagePullSecrets: [{name: %s}]\n' "$F_PULL_SECRET"
  if [[ -n "$F_NODE_KEY" ]]; then
    printf '      nodeSelector: {"%s": "%s"}\n' "$F_NODE_KEY" "$F_NODE_VALUE"
    printf '      tolerations: [{key: "%s", operator: Equal, value: "%s", effect: NoSchedule}]\n' "$F_NODE_KEY" "$F_NODE_VALUE"
  fi
  return 0
}

render_run_env() {
  [[ -n "$F_MODE" ]] && printf '            - {name: FLEET_MODE, value: %s}\n' "$(yaml_str "$F_MODE")"
  [[ -n "$F_MERGE_REF" ]] && printf '            - {name: FLEET_MERGE_REF, value: %s}\n' "$(yaml_str "$F_MERGE_REF")"
  [[ -n "$F_PR_TARGET" ]] && printf '            - {name: FLEET_PR_TARGET, value: %s}\n' "$(yaml_str "$F_PR_TARGET")"
  return 0
}

parse_postgres() {
  F_PG_IMAGE="${FLEET_POSTGRES_IMAGE:-}" F_PG_PORT="${FLEET_POSTGRES_PORT:-5432}"
  F_PG_USER="${FLEET_POSTGRES_USER:-postgres}" F_PG_PASSWORD="${FLEET_POSTGRES_PASSWORD:-postgres}" F_PG_DB="${FLEET_POSTGRES_DB:-postgres}"
  [[ -z "$F_PG_IMAGE" ]] && return 0
  [[ "$F_PG_IMAGE" =~ ^[a-z0-9][a-z0-9._/:-]*@sha256:[0-9a-f]{64}$ ]] || die "FLEET_POSTGRES_IMAGE must be pinned by digest: <image>@sha256:<64 hex>"
  [[ "$F_PG_PORT" =~ ^[1-9][0-9]{0,4}$ && "$F_PG_PORT" -le 65535 ]] || die "FLEET_POSTGRES_PORT must be a port number (1-65535)"
  local v; for v in "$F_PG_USER" "$F_PG_PASSWORD" "$F_PG_DB"; do
    [[ "$v" =~ ^[A-Za-z0-9_-]{1,63}$ ]] || die "FLEET_POSTGRES_USER, _PASSWORD and _DB may use only letters, digits, _ and - (1-63 characters)"
  done
}

# Native sidecar (restartPolicy: Always) ahead of the agent: the agent starts once pg_isready passes,
# and the sidecar stops with the Job. Each renderer prints nothing when no image is set.
render_pg_sidecar() {
  [[ -n "${F_PG_IMAGE:-}" ]] || return 0
  cat <<YAML

        - name: postgres
          image: $F_PG_IMAGE
          restartPolicy: Always
          securityContext: {readOnlyRootFilesystem: true, allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
          env:
            - {name: POSTGRES_USER, value: $(yaml_str "$F_PG_USER")}
            - {name: POSTGRES_PASSWORD, value: $(yaml_str "$F_PG_PASSWORD")}
            - {name: POSTGRES_DB, value: $(yaml_str "$F_PG_DB")}
            - {name: PGPORT, value: "$F_PG_PORT"}
            - {name: PGDATA, value: /var/lib/postgresql/data/pgdata}
          startupProbe:
            exec: {command: [pg_isready, -h, 127.0.0.1, -p, "$F_PG_PORT", -U, $(yaml_str "$F_PG_USER")]}
            periodSeconds: 2
            failureThreshold: 90
          volumeMounts:
            - {name: pgdata, mountPath: /var/lib/postgresql/data}
            - {name: pgrun, mountPath: /var/run/postgresql}
            - {name: pgtmp, mountPath: /tmp}
YAML
}

render_pg_env() {
  [[ -n "${F_PG_IMAGE:-}" ]] || return 0
  printf '\n            - {name: PGHOST, value: "127.0.0.1"}\n            - {name: PGPORT, value: "%s"}' "$F_PG_PORT"
  printf '\n            - {name: PGUSER, value: %s}\n            - {name: PGPASSWORD, value: %s}\n            - {name: PGDATABASE, value: %s}' \
    "$(yaml_str "$F_PG_USER")" "$(yaml_str "$F_PG_PASSWORD")" "$(yaml_str "$F_PG_DB")"
}

render_pg_volumes() {
  [[ -n "${F_PG_IMAGE:-}" ]] || return 0
  printf '\n        - {name: pgdata, emptyDir: {}}\n        - {name: pgrun, emptyDir: {}}\n        - {name: pgtmp, emptyDir: {}}'
}
