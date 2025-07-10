{{/*
Expand the name of the chart.
*/}}
{{- define "relvy.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "relvy.fullname" -}}
{{- $name := .Chart.Name }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "relvy.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "relvy.labels" -}}
helm.sh/chart: {{ include "relvy.chart" . }}
{{ include "relvy.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "relvy.selectorLabels" -}}
app.kubernetes.io/name: {{ include "relvy.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "relvy.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "relvy.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the image name
*/}}
{{- define "relvy.image" -}}
{{- $repositoryName := .Values.global.imageName | default "relvy/relvy-app-onprem" -}}
{{- $tag := .Values.global.imageTag | default "latest" | toString -}}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}

{{/*
Get Redis URL
*/}}
{{- define "relvy.redisUrl" -}}
{{- printf "redis://%s-redis:%v/0" (include "relvy.fullname" .) .Values.redis.service.port -}}
{{- end }}
