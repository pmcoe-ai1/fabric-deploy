# FABRIC Infrastructure Variables

variable "environment" {
  type        = string
  default     = "staging"
  description = "Environment name (staging/production)"
}

variable "location" {
  type        = string
  default     = "australiaeast"
  description = "Azure region for all resources"
}

variable "resource_group_name" {
  type        = string
  default     = "fabric-rg"
  description = "Name of the Azure Resource Group for all FABRIC resources"
}

variable "cluster_name" {
  type        = string
  default     = "fabric-aks"
  description = "Name of the AKS cluster"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.29"
  description = "Kubernetes version for AKS (latest stable)"
}

variable "system_node_count" {
  type        = number
  default     = 2
  description = "Number of nodes in the system node pool"
}

variable "system_node_vm_size" {
  type        = string
  default     = "Standard_B2s"
  description = "VM size for system node pool (B-series burstable for cost efficiency)"
}

variable "app_node_count" {
  type        = number
  default     = 2
  description = "Number of nodes in the application node pool"
}

variable "app_node_vm_size" {
  type        = string
  default     = "Standard_B2s"
  description = "VM size for application node pool"
}

variable "tags" {
  type = map(string)
  default = {
    project    = "fabric"
    managed-by = "terraform"
  }
  description = "Tags applied to all Azure resources"
}
