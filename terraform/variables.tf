variable "aws_region" {
  description = "AWS Region in the lab"
  type        = string
  default     = "eu-west-1"
}

variable "cluster_name" {
  description = "EKS Cluster Name"
  type        = string
  default     = "gitops-lab"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Keep this on a currently standard-supported minor release to avoid Extended Support charges."
  type        = string
  default     = "1.35"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.kubernetes_version)) && tonumber(split(".", var.kubernetes_version)[1]) >= 34
    error_message = "Use a supported EKS minor version (format like 1.35). Versions older than 1.34 are blocked."
  }
}