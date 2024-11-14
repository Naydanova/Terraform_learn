variable "PAT_token" {
  description = "Personal Access Token for Azure DevOps"
  type        = string
}
variable "AzDo_service_url" {
  description = "Azure DevOps service URL"
  type        = string
}
variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "environments_list" {
  description = "List of environments"
  type        = list(string)
  default     = ["dev"]
}

variable "environment_credentials" {
  description = "Map of environment credentials"
  type        = map(object({
    tenant_id                   = string
    service_principal_object_id = string
  }))
}
