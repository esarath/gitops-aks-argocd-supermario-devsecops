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

  # ClusterIP, not LoadBalancer: Azure subscriptions on the free/basic tier
  # cap public IPs per region at 3 (one of which AKS itself reserves for
  # node outbound traffic, leaving only 2 for our own services). The game
  # (k8s/deployment.yaml's supermariogame-service) needs a public IP far
  # more than the ArgoCD admin UI does, so ArgoCD gets the remaining
  # ClusterIP + `kubectl port-forward` for admin access instead of a third
  # public IP. Flip this to "LoadBalancer" if your subscription's quota
  # allows it and you want ArgoCD's UI reachable directly.
  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }
}
