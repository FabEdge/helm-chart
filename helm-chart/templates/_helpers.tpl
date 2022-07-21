{{- define "connector.labels" -}}
app: {{ .Values.connector.name }}
release: {{ .Release.Name }}
{{- end -}}

{{- define "fabDNS.labels" -}}
app: {{ .Values.fabDNS.name }}
release: {{ .Release.Name }}
{{- end -}}

{{- define "serviceHub.labels" -}}
app: {{ .Values.serviceHub.name }}
release: {{ .Release.Name }}
{{- end -}}

{{- define "fabedgeOperator.labels" -}}
app: {{ .Values.operator.name }}
release: {{ .Release.Name }}
{{- end -}}

{{- define "cert.labels" -}}
app: {{ .Values.cert.name }}
release: {{ .Release.Name }}
{{- end -}}

{{- define "cloudAgent.labels" -}}
app: {{ .Values.cloudAgent.name }}
release: {{ .Release.Name }}
{{- end -}}

{{- define "serviceHub.mode" -}}
{{ (eq .Values.cluster.role "host") | ternary "server" "client" }}
{{- end }}

{{- define "cniType" -}}
{{- .Values.cluster.cniType | default "" | lower -}}
{{- end }}

{{- define "operator.tlsName" -}}
{{- .Values.operator.name }}-tls
{{- end }}

{{- define "serviceHub.tlsName" -}}
{{- .Values.serviceHub.name }}-tls
{{- end }}

{{- define "connector.node.addresses" -}}
{{- if .Values.cluster.connectorNodeAddresses -}}
{{ join "," .Values.cluster.connectorNodeAddresses -}}
{{- else }}
  {{- $ips := list -}}
  {{- range $index, $node := (lookup "v1" "Node" "" "").items -}}
    {{- $isConnector := true -}}
    {{- range $_, $label := $.Values.cluster.connectorLabels -}}
    {{- $parts := regexSplit "=" $label 2 -}}
    {{- $key := first $parts -}}
    {{- $value := last $parts -}}
    {{- $isConnector = and $isConnector (hasKey $node.metadata.labels $key) (eq (get $node.metadata.labels $key) $value) -}}
    {{- end -}}
    {{- if $isConnector -}}
      {{- range $node.status.addresses -}}
        {{- if eq .type "InternalIP" -}}
          {{- $ips = append $ips .address -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- join "," $ips -}}
{{- end }}
{{- end }}

{{- define "cluster.publicAddresses" -}}
{{- if .Values.cluster.publicAddresses -}}
    {{- join "," .Values.cluster.publicAddresses -}}
{{- else -}}
    {{- join "," .Values.cluster.connectorPublicAddresses -}}
{{- end -}}
{{- end }}