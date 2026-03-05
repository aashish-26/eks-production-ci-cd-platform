{{- define "eks-app.name" -}}
{{- default .Chart.Name .Values.nameOverride -}}
{{- end -}}

{{/* Fullname: truncated to 63 chars as per Kubernetes label spec */}}
{{- define "eks-app.fullname" -}}
{{- printf "%s-%s" (include "eks-app.name" .) .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Common labels shared across all resources */}}
{{- define "eks-app.labels" -}}
app.kubernetes.io/name: {{ include "eks-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
