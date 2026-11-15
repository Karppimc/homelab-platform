{{/* Labels on every resource of the baseline */}}
{{- define "namespace-baseline.labels" -}}
app.kubernetes.io/name: namespace-baseline
app.kubernetes.io/instance: {{ .Values.name }}
app.kubernetes.io/part-of: {{ .Values.name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
platform.home.arpa/owner: {{ .Values.owner | quote }}
{{- end -}}
