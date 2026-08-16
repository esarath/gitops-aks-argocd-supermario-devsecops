output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks_cluster.name
}

output "kube_config_raw" {
  value     = azurerm_kubernetes_cluster.aks_cluster.kube_config_raw
  sensitive = true
}

output "get_credentials_command" {
  description = "Run this to configure kubectl/argocd CLI locally"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.aks_rg.name} --name ${azurerm_kubernetes_cluster.aks_cluster.name}"
}

output "argocd_namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}

output "sonarqube_namespace" {
  value = kubernetes_namespace.sonarqube.metadata[0].name
}

output "get_argocd_external_ip_command" {
  value = "kubectl get svc argocd-server -n ${var.argocd_namespace}"
}

output "get_sonarqube_external_ip_command" {
  value = "kubectl get svc sonarqube-sonarqube -n ${var.sonarqube_namespace}"
}

output "get_argocd_admin_password_command" {
  description = "ArgoCD admin password is auto-generated on install; this reads it back"
  value       = "kubectl -n ${var.argocd_namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
