#!/usr/bin/env bash
set -uo pipefail
# shellcheck source=../lib/harness.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/harness.sh"
# shellcheck source=../lib/dispatch-env.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dispatch-env.sh"
stub_cluster
DIGEST="sha256:$(printf '0123456789abcdef%.0s' 1 2 3 4)"
# Job name, secret name and commit change with each reset_env repo; mask them so only the template is compared.
job() { sed -n '/^kind: Job/,/^---/p' "$TMP/out" | sed -E '/^---/d; s/fleet-[0-9a-z]+-[0-9a-f]{5}(-[0-9a-f]{5})?/fleet-JOB/g; s/(FLEET_COMMIT, value: ")[0-9a-f]{40}/\1COMMIT/'; }

reset_env; dispatch --dry-run; plain="$(job)"
# The same manifest with the three postgres hooks cut out of manifest.sh: what render_job printed before 058.
cp -R "$FLEET_ROOT" "$TMP/old"
# shellcheck disable=SC2016 # a literal $( in the pattern
sed -i.bak 's/\$(render_pg_[a-z]*)//' "$TMP/old/lib/manifest.sh"
reset_env; FLEET="$TMP/old/bin/specclaw-fleet" dispatch --dry-run; before="$(job)"
reset_env; FLEET_POSTGRES_IMAGE="postgres@$DIGEST" FLEET_POSTGRES_PORT=55432 dispatch --dry-run; pg_rc=$?; pg="$(job)"

unchanged_without_postgres() { [[ -n "$plain" && "$plain" == "$before" ]] && ! grep -qi "postgres\|PGPORT" <<<"$plain"; }
sidecar_before_agent() {
  (( pg_rc == 0 )) || return 1
  local init; init="$(sed -n '/initContainers:/,/^      containers:/p' <<<"$pg")"
  [[ "$(grep -o 'name: [a-z]*$' <<<"$init" | head -2 | tr '\n' ' ')" == "name: postgres name: agent " ]] \
    && grep -q "image: postgres@$DIGEST" <<<"$init" && grep -q "restartPolicy: Always" <<<"$init" \
    && grep -q 'command: \[pg_isready, -h, 127.0.0.1, -p, "55432", -U, "postgres"\]' <<<"$init" \
    && grep -q '{name: PGPORT, value: "55432"}' <<<"$(sed -n '/- name: agent/,$p' <<<"$init")" \
    && grep -q '{name: PGHOST, value: "127.0.0.1"}' <<<"$init" \
    && grep -q "{name: pgdata, emptyDir: {}}" <<<"$pg" \
    && python3 -c 'import sys,yaml; yaml.safe_load(sys.stdin)' <<<"$pg"
}
refused_all=1
while IFS='|' read -r field bad; do
  reset_env; read -ra kv <<<"$bad"; env "${kv[@]}" "$FLEET" dispatch "$CHANGE" > "$TMP/out" 2>&1 && refused_all=0
  nothing_applied && grep -q "FLEET_POSTGRES_$field" "$TMP/out" || { refused_all=0; echo "  not refused for $field: $bad"; }
done <<ROWS
IMAGE|FLEET_POSTGRES_IMAGE=postgres:16
IMAGE|FLEET_POSTGRES_IMAGE=postgres@sha256:abc
PORT|FLEET_POSTGRES_IMAGE=postgres@$DIGEST FLEET_POSTGRES_PORT=0
PORT|FLEET_POSTGRES_IMAGE=postgres@$DIGEST FLEET_POSTGRES_PORT=70000
USER|FLEET_POSTGRES_IMAGE=postgres@$DIGEST FLEET_POSTGRES_USER=a:b
PASSWORD|FLEET_POSTGRES_IMAGE=postgres@$DIGEST FLEET_POSTGRES_PASSWORD=p"q
DB|FLEET_POSTGRES_IMAGE=postgres@$DIGEST FLEET_POSTGRES_DB=x}y
IMAGE|FLEET_POSTGRES_PORT=55432
ROWS
refuses() { (( refused_all == 1 )); }

check "R058 AC-3 without postgres the Job is byte-identical to the pre-058 render" unchanged_without_postgres
check "R058 AC-3 postgres runs as a native sidecar before the agent, gated by pg_isready; the agent gets PG* env; valid YAML" sidecar_before_agent
check "R058 AC-2 an unpinned image, a bad port, user, password or db, or postgres settings without an image are refused, naming the field, before anything is created" refuses
finish
