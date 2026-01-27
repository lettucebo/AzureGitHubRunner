output "resource_group_name" {
  description = "Resource Group 名稱"
  value       = azurerm_resource_group.rg.name
}

output "vm_name" {
  description = "Virtual Machine 名稱"
  value       = azurerm_linux_virtual_machine.vm.name
}

output "vm_id" {
  description = "Virtual Machine ID"
  value       = azurerm_linux_virtual_machine.vm.id
}

output "public_ip_address" {
  description = "VM 公開 IP 位址"
  value       = azurerm_public_ip.pip.ip_address
}

output "private_ip_address" {
  description = "VM 私有 IP 位址"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "ssh_command" {
  description = "SSH 連線指令"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "vm_size" {
  description = "VM 規格大小"
  value       = azurerm_linux_virtual_machine.vm.size
}

output "runner_count" {
  description = "已配置的 GitHub Runners 數量"
  value       = var.runner_count
}

output "runner_services" {
  description = "GitHub Runner systemd 服務名稱"
  value       = [for i in range(1, var.runner_count + 1) : "actions-runner-${i}.service"]
}

output "check_runners_command" {
  description = "檢查 Runners 狀態的指令"
  value       = "sudo systemctl status actions-runner-*.service"
}

output "vm_fqdn" {
  description = "VM 完整網域名稱（如果有設定）"
  value       = azurerm_public_ip.pip.fqdn
}

output "is_spot_vm" {
  description = "是否為 Spot VM"
  value       = var.enable_spot_vm
}

output "spot_instance_info" {
  description = "Spot VM 配置資訊"
  value = var.enable_spot_vm ? {
    eviction_policy = var.spot_eviction_policy
    max_bid_price   = var.spot_max_bid_price == -1 ? "隨需價格" : "$${var.spot_max_bid_price}/小時"
    cost_savings    = "預估節省 70-90% 成本"
  } : null
}
