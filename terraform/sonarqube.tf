resource "kubernetes_namespace" "sonarqube" {
  metadata {
    name = var.sonarqube_namespace
  }

  depends_on = [azurerm_kubernetes_cluster_node_pool.user_pool]
}

# Official SonarSource Helm chart. Uses the chart's bundled PostgreSQL
# subchart (fine for a POC/single-node setup) rather than an external DB —
# swap postgresql.enabled to false and point postgresql.jdbcOverwrite at
# an external database for anything beyond a POC.
resource "helm_release" "sonarqube" {
  name       = "sonarqube"
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  version    = var.sonarqube_chart_version
  namespace  = kubernetes_namespace.sonarqube.metadata[0].name

  # SonarQube requires this on the node running it; AKS nodes normally
  # already satisfy it, but Elasticsearch (which SonarQube embeds) fails
  # to start otherwise. Left in for portability, no-op if already sufficient.
  set {
    name  = "elasticsearch.sysctlInitContainer.enabled"
    value = "true"
  }

  set {
    name  = "service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "service.externalPort"
    value = "9000"
  }

  # The chart's bundled Postgres subchart defaults to a pinned Bitnami tag
  # (11.14.0-debian-10-r22) that Bitnami removed from Docker Hub after their
  # 2025 catalog restructuring (versioned tags are now paywalled, only
  # `latest` remains free) — pin to `latest` so the pull actually succeeds.
  set {
    name  = "postgresql.image.tag"
    value = "latest"
  }

  timeout = 900
}
