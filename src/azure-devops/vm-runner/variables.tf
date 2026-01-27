variable "resource_group_name" {
  description = "Azure Resource Group 名稱"
  type        = string
  default     = "AzureDevOps"
}

variable "location" {
  description = "Azure 區域（台灣用戶推薦：eastasia=香港 或 southeastasia=新加坡）"
  type        = string
  default     = "eastasia"

  validation {
    condition     = can(regex("^[a-z]+$", var.location))
    error_message = "Location 必須是有效的 Azure 區域名稱（小寫英文）。"
  }
}

variable "prefix" {
  description = "資源名稱前綴"
  type        = string
  default     = "ado-runner"
}

variable "vm_size" {
  description = "VM 規格大小"
  type        = string
  default     = "Standard_D4s_v5"

  validation {
    condition     = can(regex("^Standard_", var.vm_size))
    error_message = "VM size 必須是有效的 Azure VM 規格。"
  }
}

variable "os_disk_type" {
  description = "OS 磁碟類型"
  type        = string
  default     = "Premium_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS"], var.os_disk_type)
    error_message = "OS disk type 必須是 Standard_LRS, StandardSSD_LRS 或 Premium_LRS。"
  }
}

variable "os_disk_size_gb" {
  description = "OS 磁碟大小 (GB)"
  type        = number
  default     = 128

  validation {
    condition     = var.os_disk_size_gb >= 30 && var.os_disk_size_gb <= 4095
    error_message = "OS disk size 必須在 30GB 到 4095GB 之間。"
  }
}

variable "admin_username" {
  description = "VM 管理員帳號名稱"
  type        = string
  default     = "azureuser"

  validation {
    condition     = length(var.admin_username) >= 1 && length(var.admin_username) <= 64
    error_message = "Admin username 長度必須在 1-64 字元之間。"
  }
}

variable "ssh_public_key" {
  description = "SSH 公鑰內容（用於 VM 登入）"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^ssh-", var.ssh_public_key))
    error_message = "SSH public key 必須是有效的公鑰格式（以 ssh- 開頭）。"
  }
}

variable "ssh_source_address_prefix" {
  description = "允許 SSH 連線的來源 IP 範圍（使用 CIDR 格式或 '*' 允許所有）"
  type        = string
  default     = "*"

  validation {
    condition     = can(cidrhost(var.ssh_source_address_prefix, 0)) || var.ssh_source_address_prefix == "*"
    error_message = "SSH source address prefix 必須是有效的 CIDR 格式或 '*'。"
  }
}

variable "use_spot_instance" {
  description = "是否使用 Spot Instance（可節省 70-90% 費用，但有被回收風險）"
  type        = bool
  default     = true
}

variable "azure_devops_url" {
  description = "Azure DevOps 組織 URL（例如：https://dev.azure.com/your-org）"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^https://dev\\.azure\\.com/[a-zA-Z0-9-]+$", var.azure_devops_url))
    error_message = "Azure DevOps URL 必須是有效的格式（例如：https://dev.azure.com/your-org）。"
  }
}

variable "azure_devops_token" {
  description = "Azure DevOps Personal Access Token (PAT)，需要 Agent Pools (Read & manage) 權限"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.azure_devops_token) > 0
    error_message = "Azure DevOps token 不能為空。"
  }
}

variable "azure_devops_pool_name" {
  description = "Azure DevOps Agent Pool 名稱"
  type        = string
  default     = "Default"

  validation {
    condition     = length(var.azure_devops_pool_name) > 0
    error_message = "Agent pool name 不能為空。"
  }
}

variable "runner_count" {
  description = "要部署的 Agent 數量（在同一台 VM 上）"
  type        = number
  default     = 3

  validation {
    condition     = var.runner_count >= 1 && var.runner_count <= 10
    error_message = "Runner count 必須在 1 到 10 之間。"
  }
}

variable "tags" {
  description = "資源標籤"
  type        = map(string)
  default = {
    project     = "azure-devops-runner"
    environment = "production"
    managed_by  = "terraform"
  }
}
