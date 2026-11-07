# shellcheck shell=bash
render_secret() {
  cat <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: $F_JOB
  namespace: $F_NS
  labels:
    app.kubernetes.io/part-of: specclaw-fleet
  ownerReferences:
    - {apiVersion: batch/v1, kind: Job, name: $F_JOB, uid: "$2"}
type: Opaque
data:
  credential: $1
YAML
}

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
  activeDeadlineSeconds: $F_DEADLINE
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app.kubernetes.io/part-of: specclaw-fleet
        specclaw.fleet/agent: $F_AGENT
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      securityContext: {runAsNonRoot: true, runAsUser: 1000, runAsGroup: 1000, fsGroup: 1000}
      initContainers:
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
            - {name: HTTPS_PROXY, value: "http://fleet-egress:3128"}
            - {name: HTTP_PROXY, value: "http://fleet-egress:3128"}
            - {name: NO_PROXY, value: "localhost,127.0.0.1"}
          volumeMounts:
            - {name: work, mountPath: /fleet/work}
            - {name: home, mountPath: /home/agent}
            - {name: status, mountPath: /fleet/status}
            - {name: cred, mountPath: /run/fleet, readOnly: true}
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
            - {name: HTTPS_PROXY, value: "http://fleet-egress:3128"}
          volumeMounts:
            - {name: home, mountPath: /home/agent}
            - {name: status, mountPath: /fleet/status}
      volumes:
        - {name: work, emptyDir: {}}
        - {name: home, emptyDir: {}}
        - {name: status, emptyDir: {}}
        - {name: cred, secret: {secretName: $F_JOB}}
YAML
}
