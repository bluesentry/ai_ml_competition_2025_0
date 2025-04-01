variable "domain" {
  description = "Base domain for the website"
  type        = string

  default = null
}

variable "ecr_repos" {
  description = "A list of ECR repository names. The first item in the list represents the repository for the dynamic website image (used for Docker image builds)."
  type        = map(string)

  default = {}
}

variable "eks_cluster_version" {
  description = "Version of kubernetes running on cluster"
  type        = string

  default = null
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string

  default = null
}

variable "environment" {
  description = "Environment name"
  type        = string

  default = null
}

variable "region" {
  description = "AWS region"
  type        = string

  default = null
}

variable "tags" {
  description = "Universal tags"
  type        = map(string)

  default = {}
}

variable "vpc_cidr" {
  description = "VPC cidr block"
  type        = string

  default = null
}

variable "vpc_redundancy" {
  description = "Redundancy for this VPCs NAT gateways"
  type        = bool

  default = false
}

variable "github_actions_oidc_role" {
  type        = string
  description = "Name of the keypair to ssh into the instance"
  default     = null
}