{{/*
  ============================================================
  Helm Helpers — named templates reused across all manifests.
  ============================================================
*/}}

{{/* Chart name, honouring an optional nameOverride */}}
{{- define "eks-app.name" -}}
{{- default .Chart.Name .Values.nameOverride -}}
{{- end -}}

{{/*
  Full resource name: <chart-name>-<release-name>.
  Truncated to 63 chars and stripped of a trailing "-" to comply
  with the Kubernetes label/name length limit (RFC 1123).
*/}}
{{- define "eks-app.fullname" -}}
{{- printf "%s-%s" (include "eks-app.name" .) .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
  Standard labels applied to every resource in this chart.
  Using these on both the Deployment selector and pod template
  ensures Services and HPAs can always find the correct pods.
*/}}
{{- define "eks-app.labels" -}}
app.kubernetes.io/name: {{ include "eks-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
  ServiceAccount name helper.
  Returns the fullname if create=true, otherwise the explicitly
  provided name, falling back to "default".
*/}}
{{- define "eks-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{ include "eks-app.fullname" . }}
{{- else -}}
{{ .Values.serviceAccount.name | default "default" }}
{{- end -}}
{{- end -}}
