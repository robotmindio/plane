{{/*
Expand the name of the chart.
*/}}
{{- define "plane.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Full name with release prefix.
*/}}
{{- define "plane.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "plane.labels" -}}
helm.sh/chart: {{ include "plane.name" . }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: plane
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for a specific component.
*/}}
{{- define "plane.selectorLabels" -}}
app.kubernetes.io/name: {{ include "plane.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Secret name — either user-provided or generated.
*/}}
{{- define "plane.secretName" -}}
{{- if .Values.secrets.existingSecret }}
{{- .Values.secrets.existingSecret }}
{{- else }}
{{- include "plane.fullname" . }}-secrets
{{- end }}
{{- end }}

{{/*
Image helper: registry/image:tag
*/}}
{{- define "plane.image" -}}
{{- .registry }}/{{ .name }}:{{ .tag }}
{{- end }}

{{/*
PostgreSQL connection URL.
Passwords are hex-only when generated, but we urlencode for safety.
*/}}
{{- define "plane.databaseUrl" -}}
{{- if .Values.postgres.local -}}
postgresql://{{ .Values.postgres.user }}:{{ .Values.postgres.password | urlquery }}@{{ include "plane.fullname" . }}-postgres:5432/{{ .Values.postgres.database }}
{{- else -}}
{{- .Values.postgres.externalUrl }}
{{- end -}}
{{- end }}

{{/*
Redis connection URL.
*/}}
{{- define "plane.redisUrl" -}}
{{- if .Values.redis.local -}}
redis://{{ include "plane.fullname" . }}-redis:6379/
{{- else -}}
{{- .Values.redis.externalUrl }}
{{- end -}}
{{- end }}

{{/*
AMQP connection URL.
*/}}
{{- define "plane.amqpUrl" -}}
{{- if .Values.rabbitmq.local -}}
amqp://{{ .Values.rabbitmq.user }}:{{ .Values.rabbitmq.password | urlquery }}@{{ include "plane.fullname" . }}-rabbitmq:5672/{{ .Values.rabbitmq.vhost }}
{{- else -}}
{{- .Values.rabbitmq.externalUrl }}
{{- end -}}
{{- end }}

{{/*
S3 endpoint URL.
*/}}
{{- define "plane.s3Endpoint" -}}
{{- if .Values.minio.local -}}
http://{{ include "plane.fullname" . }}-minio:9000
{{- else -}}
{{- .Values.minio.external.endpoint }}
{{- end -}}
{{- end }}

{{/*
Config checksum annotation — triggers rolling restart on config/secret changes.
*/}}
{{- define "plane.configChecksum" -}}
checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
checksum/secret: {{ include (print $.Template.BasePath "/secrets.yaml") . | sha256sum }}
{{- end }}
