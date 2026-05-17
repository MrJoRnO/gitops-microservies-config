variable "vpc_name" {
  type        = string
  description = "The name of the VPC"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones in the region"
}

variable "private_subnets" {
  type        = list(string)
  description = "List of private subnet CIDR blocks"
}

variable "public_subnets" {
  type        = list(string)
  description = "List of public subnet CIDR blocks"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name — used to tag subnets for ALB controller and Cluster Autoscaler discovery"
}

variable "single_nat_gateway" {
  type        = bool
  description = "Single NAT GW (true = cost-saving for dev/staging; false = one per AZ for prod HA)"
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}