// ============================================================================
// 參數範例檔案
// 複製此檔案為 main.bicepparam 並填入您的設定
// ============================================================================

using 'main.bicep'

// 可選功能
param enableMonitoring = true // Container Insights
param enableAcr = false       // 使用 GitHub 官方 image，不需要 ACR
param logRetentionDays = 30   // Log 保留天數

// 標籤
param tags = {
  environment: 'github-runner'
  managedBy: 'bicep'
  SecurityControl: 'Ignore'
}
