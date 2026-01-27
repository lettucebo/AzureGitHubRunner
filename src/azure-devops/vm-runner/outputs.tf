output "resource_group_name" {
  description = "Resource Group 名稱"
  value       = azurerm_resource_group.rg.name
}

output "vm_name" {
  description = "VM 名稱"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "public_ip_address" {
  description = "VM 公網 IP 位址"
  value       = azurerm_public_ip.pip.ip_address
}

output "vm_id" {
  description = "VM Resource ID"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "is_spot_instance" {
  description = "是否為 Spot Instance"
  value       = var.use_spot_instance
}

output "agent_pool_name" {
  description = "Azure DevOps Agent Pool 名稱"
  value       = var.azure_devops_pool_name
}

output "runner_count" {
  description = "部署的 Agent 數量"
  value       = var.runner_count
}
