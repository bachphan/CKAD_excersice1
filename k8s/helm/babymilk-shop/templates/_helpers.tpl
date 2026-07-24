{{- define "babymilk.commonLabels" -}}
app.kubernetes.io/part-of: babymilk-shop
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
