variable "resource_group_name" {
  description = "Azure Resource Group 名稱"
  type        = string
  default     = "Github"
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
  default     = "gh-runner"
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
  default     = "demouser"

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
}

variable "github_token" {
  description = "GitHub Personal Access Token（需要 repo 和 admin:org 權限）"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.github_token) > 0
    error_message = "GitHub token 不能為空。"
  }
}

variable "github_repo_url" {
  description = "GitHub Repository 或 Organization URL（例如：https://github.com/owner/repo 或 https://github.com/org-name）"
  type        = string

  validation {
    condition     = can(regex("^https://github\\.com/[^/]+(/[^/]+)?/?$", var.github_repo_url))
    error_message = "GitHub URL 必須是有效格式：https://github.com/owner/repo（repository）或 https://github.com/org-name（organization）"
  }
}

variable "runner_count" {
  description = "要建立的 GitHub Runner 數量"
  type        = number
  default     = 6

  validation {
    condition     = var.runner_count >= 1 && var.runner_count <= 10
    error_message = "Runner count 必須在 1-10 之間。"
  }
}

variable "runner_labels" {
  description = "GitHub Runner 標籤（逗號分隔，例如：self-hosted,linux,x64）"
  type        = string
  default     = "self-hosted,linux,x64,azure"
}

variable "enable_spot_vm" {
  description = "是否使用 Azure Spot VM（可節省高達 90% 成本，但可能被回收）"
  type        = bool
  default     = true
}

variable "spot_eviction_policy" {
  description = "Spot VM 回收策略：Deallocate（保留 VM 配置，只收磁碟費用）或 Delete（完全刪除）"
  type        = string
  default     = "Deallocate"

  validation {
    condition     = contains(["Deallocate", "Delete"], var.spot_eviction_policy)
    error_message = "Eviction policy 必須是 Deallocate 或 Delete。"
  }
}

variable "spot_max_bid_price" {
  description = "Spot VM 最高出價（USD/小時），-1 表示願意支付最高到隨需價格（降低被回收風險）"
  type        = number
  default     = -1

  validation {
    condition     = var.spot_max_bid_price == -1 || var.spot_max_bid_price > 0
    error_message = "Max bid price 必須是 -1（隨需價格）或大於 0 的數字。"
  }
}

variable "tags" {
  description = "所有資源的標籤"
  type        = map(string)
  default = {
    Environment = "GitHub-Runners"
    ManagedBy   = "Terraform"
  SecurityControl = "Ignore" }
}
