variable "env" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "system_node_group" {
  type = object({
    instance_types = list(string)
    desired_size   = number
  })
}

variable "app_node_group" {
  type = object({
    instance_types = list(string)
    min_size       = number
    max_size       = number
  })
}

variable "cluster_endpoint_public_access" {
  type        = bool
  description = "Expose the API server publicly. Keep true for dev/staging convenience; set false for prod and use a bastion/VPN."
  default     = true
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default     = {}
}