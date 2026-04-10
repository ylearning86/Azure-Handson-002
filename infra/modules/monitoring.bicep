// infra/modules/monitoring.bicep
// 要件: ログを蓄積し3年間保管。ダッシュボード等による状況の可視化

@description('リソース名のプレフィックス')
param prefix string

@description('リソースのロケーション')
param location string

@description('環境名')
@allowed(['dev', 'test', 'prod'])
param env string

// 要件: ログ保管期間 3年 (1095日)
// ※ ハンズオンでは 90日 に設定 (コスト考慮)
@description('ログ保持期間 (日数)')
param retentionInDays int = 90

// --- Log Analytics Workspace ---
// 要件: 監視ログの一元化、セキュリティイベントアラートの一元化
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${prefix}-${env}'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

// --- Application Insights ---
// 要件: アプリケーション処理時間の性能見積り、画面遷移・操作ログ等の分析
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${prefix}-${env}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    RetentionInDays: retentionInDays
  }
}

output logAnalyticsId string = logAnalytics.id
output logAnalyticsName string = logAnalytics.name
output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
