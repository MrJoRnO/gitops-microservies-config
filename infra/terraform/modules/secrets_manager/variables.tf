variable "secret_name" {
  type        = string
}

variable "db_details" {
  type        = string
  sensitive   = true
}

variable "tags" {
  type        = map(string)
}