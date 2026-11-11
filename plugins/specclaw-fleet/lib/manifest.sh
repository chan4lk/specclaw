# shellcheck shell=bash
render_job() {
  cat <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: $F_JOB
  namespace: $F_NS
  labels:
    specclaw.fleet/agent: $F_AGENT
    specclaw.fleet/assignee: "$F_HASH"
    specclaw.fleet/change: "$F_LABEL"
spec:
  backoffLimit: 0
  activeDeadlineSeconds: $((F_DEADLINE + 600))
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app.kubernetes.io/part-of: specclaw-fleet
        specclaw.fleet/agent: $F_AGENT
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, fsGroup: 1000, seccompProfile: {type: RuntimeDefault}}
$(render_pod_extras)
      initContainers:$(render_pg_sidecar)
        - name: agent
          image: $F_IMAGE
          command: ["/opt/fleet/entrypoint.sh"]
          securityContext: {readOnlyRootFilesystem: true, allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
          envFrom: [{secretRef: {name: fleet-azdo}}]
          env:
            - {name: FLEET_AGENT, value: $F_AGENT}
            - {name: FLEET_CHANGE, value: $(yaml_str "$F_CHANGE")}
            - {name: FLEET_REF, value: $(yaml_str "$F_REF")}
            - {name: FLEET_REPO_URL, value: $(yaml_str "$F_REPO")}
            - {name: FLEET_WORK_ITEM, value: "$F_WI"}
            - {name: FLEET_AGENT_TIMEOUT, value: "$F_DEADLINE"}
            - {name: FLEET_CLAUDE_VERSION, value: $(yaml_str "$F_CLAUDE_VERSION")}
            - {name: FLEET_COMMIT, value: "$F_COMMIT"}
            - {name: FLEET_AZDO_CONFIG, value: $(yaml_str "$F_AZDO_CONFIG")}
$(render_run_env)
            - {name: TMPDIR, value: /tmp}
            - {name: HTTPS_PROXY, value: "http://fleet-egress.specclaw-fleet-egress:3128"}
            - {name: HTTP_PROXY, value: "http://fleet-egress.specclaw-fleet-egress:3128"}
            - {name: NO_PROXY, value: "localhost,127.0.0.1"}$(render_pg_env)
          volumeMounts:
            - {name: work, mountPath: /fleet/work}
            - {name: home, mountPath: /home/agent}
            - {name: status, mountPath: /fleet/status}
            - {name: cred, mountPath: /run/fleet, readOnly: true}
            - {name: codex, mountPath: /fleet/codex}
            - {name: tmp, mountPath: /tmp}
      containers:
        - name: writeback
          image: $F_IMAGE
          command: ["/opt/fleet/writeback.sh"]
          securityContext: {readOnlyRootFilesystem: true, allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
          envFrom: [{secretRef: {name: fleet-vault-writer}}]
          env:
            - {name: FLEET_AGENT, value: $F_AGENT}
            - {name: FLEET_VAULT, value: $(yaml_str "$F_VAULT")}
            - {name: FLEET_SECRET, value: $(yaml_str "$F_SECRET")}
            - {name: HOME, value: /fleet/wbhome}
            - {name: HTTPS_PROXY, value: "http://fleet-egress.specclaw-fleet-egress:3128"}
          volumeMounts:
            - {name: codex, mountPath: /fleet/codex, readOnly: true}
            - {name: status, mountPath: /fleet/status, readOnly: true}
            - {name: wbhome, mountPath: /fleet/wbhome}
      volumes:
        - {name: work, emptyDir: {}}
        - {name: home, emptyDir: {}}
        - {name: status, emptyDir: {}}
        - {name: codex, emptyDir: {}}
        - {name: tmp, emptyDir: {}}
        - {name: wbhome, emptyDir: {}}
        - {name: cred, secret: {secretName: $F_SECRET_OBJ}}$(render_pg_volumes)
YAML
}
