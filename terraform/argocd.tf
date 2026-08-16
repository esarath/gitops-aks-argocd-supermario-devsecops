resource "kubernetes_namespace" "argocd" {
  metadata {
    name = var.argocd_namespace
  }

  depends_on = [azurerm_kubernetes_cluster_node_pool.user_pool]
}

# Official Argo Helm chart instead of applying the raw upstream install.yaml
# via a null_resource — this gives Terraform a real, trackable resource
# (upgrade/destroy work through `terraform apply`/`destroy` normally) and
# lets the argocd-server Service type be set declaratively below, instead
# of a separate imperative kubectl patch step.
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }

  # Match the original POC's port mapping (80/443 -> server's 8080).
  set {
    name  = "server.service.servicePortHttp"
    value = "80"
  }
  set {
    name  = "server.service.servicePortHttps"
    value = "443"
  }
}
