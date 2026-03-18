# Grafana Tempo — Distributed Tracing
# Design Reference: Section 9.1 (Observability Stack)
# Task F-03: Deploy Tempo for trace collection and correlation
#
# Deployed via Helm to monitoring namespace.
# Configured as Grafana data source for trace queries.
# Trace-to-log correlation: Tempo → Loki linking via traceID.
# OpenTelemetry Collector deployed for trace ingestion.

resource "helm_release" "tempo" {
  name       = "tempo"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "tempo"
  version    = "1.10.1"
  namespace  = "monitoring"

  depends_on = [
    kubernetes_namespace.fabric["monitoring"],
    helm_release.kube_prometheus_stack,
  ]

  set {
    name  = "tempo.nodeSelector.fabric/pool"
    value = "system"
  }

  # Storage — local PVC
  set {
    name  = "persistence.enabled"
    value = "true"
  }

  set {
    name  = "persistence.size"
    value = "10Gi"
  }

  # Retention — 7 days
  set {
    name  = "tempo.retention"
    value = "168h"
  }

  # Enable metrics generator for trace-derived metrics
  set {
    name  = "tempo.metricsGenerator.enabled"
    value = "true"
  }

  set {
    name  = "tempo.metricsGenerator.remoteWriteUrl"
    value = "http://kube-prometheus-stack-prometheus.monitoring:9090/api/v1/write"
  }

  # OTLP receivers (gRPC + HTTP)
  set {
    name  = "tempo.receivers.otlp.protocols.grpc.endpoint"
    value = "0.0.0.0:4317"
  }

  set {
    name  = "tempo.receivers.otlp.protocols.http.endpoint"
    value = "0.0.0.0:4318"
  }

  # Resource requests
  set {
    name  = "tempo.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "tempo.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "tempo.resources.limits.cpu"
    value = "500m"
  }

  set {
    name  = "tempo.resources.limits.memory"
    value = "512Mi"
  }
}

# OpenTelemetry Collector — trace ingestion pipeline
resource "helm_release" "otel_collector" {
  name       = "otel-collector"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  version    = "0.92.0"
  namespace  = "monitoring"

  depends_on = [
    kubernetes_namespace.fabric["monitoring"],
    helm_release.tempo,
  ]

  # Required since chart v0.92.0
  set {
    name  = "image.repository"
    value = "otel/opentelemetry-collector-contrib"
  }

  set {
    name  = "mode"
    value = "deployment"
  }

  set {
    name  = "replicaCount"
    value = "1"
  }

  set {
    name  = "nodeSelector.fabric/pool"
    value = "system"
  }

  # Collector config — receive OTLP, export to Tempo
  set {
    name  = "config.receivers.otlp.protocols.grpc.endpoint"
    value = "0.0.0.0:4317"
  }

  set {
    name  = "config.receivers.otlp.protocols.http.endpoint"
    value = "0.0.0.0:4318"
  }

  set {
    name  = "config.exporters.otlp.endpoint"
    value = "tempo.monitoring:4317"
  }

  set {
    name  = "config.exporters.otlp.tls.insecure"
    value = "true"
  }

  set {
    name  = "config.service.pipelines.traces.receivers[0]"
    value = "otlp"
  }

  set {
    name  = "config.service.pipelines.traces.exporters[0]"
    value = "otlp"
  }

  # Resource requests
  set {
    name  = "resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "resources.requests.memory"
    value = "64Mi"
  }

  set {
    name  = "resources.limits.cpu"
    value = "200m"
  }

  set {
    name  = "resources.limits.memory"
    value = "256Mi"
  }
}
