variable "resource_group_name" {
  description = "The name of the Azure resource group for the AKS cluster"
  type        = string
  default     = "myAksResourceGroup"
}

variable "resource_group_location" {
  description = "Azure region for the resource group / AKS cluster"
  type        = string
  default     = "eastus2"
}

variable "aks_cluster_name" {
  description = "The name of the AKS cluster"
  type        = string
  default     = "myAksCluster"
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster"
  type        = string
  default     = "myaksdns"
}

variable "vm_size" {
  description = "VM size for both the system and user node pools"
  type        = string
  default     = "Standard_D2s_v6"
}

variable "system_node_count" {
  description = "Node count for the system (control-plane-adjacent) node pool"
  type        = number
  default     = 1
}

variable "user_node_count" {
  description = "Node count for the user (workload) node pool"
  type        = number
  default     = 1
}

variable "argocd_namespace" {
  description = "Kubernetes namespace to install ArgoCD into"
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart (argoproj.github.io/argo-helm)"
  type        = string
  default     = "7.7.11"
}

variable "sonarqube_namespace" {
  description = "Kubernetes namespace to install SonarQube into"
  type        = string
  default     = "sonarqube"
}

variable "sonarqube_chart_version" {
  description = "Version of the sonarqube Helm chart (SonarSource.github.io/helm-chart-sonarqube)"
  type        = string
  default     = "10.6.1"
}
