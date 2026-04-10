// infra/main.bicep
// メインテンプレート: 全モジュールをオーケストレーション

// --- パラメータ ---
@description('リソース名のプレフィックス (一意の文字列)')
param prefix string

@description('リソースのロケーション (要件: 日本国内リージョン)')
param location string = 'japaneast'

@description('環境名 (要件: 本番/テスト/開発環境を明確に分離)')
@allowed(['dev', 'test', 'prod'])
param env string = 'dev'

@description('Application Gateway (WAF) をデプロイするか')
param deployAppGateway bool = false

// --- モジュール: ネットワーク ---
module network 'modules/network.bicep' = {
  name: 'deploy-network'
  params: {
    prefix: prefix
    location: location
    env: env
  }
}

// --- モジュール: 監視 ---
module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    prefix: prefix
    location: location
    env: env
    // 本番環境ではログ保持期間を延長 (要件: 3年間)
    retentionInDays: env == 'prod' ? 730 : 90
  }
}

// --- モジュール: Application Gateway + WAF ---
// 要件: L3～L7 層で対策可能な仕組み、不正通信の遮断
module appGateway 'modules/appgateway.bicep' = if (deployAppGateway) {
  name: 'deploy-appgateway'
  params: {
    prefix: prefix
    location: location
    env: env
    subnetId: network.outputs.snetAppGwId
    logAnalyticsId: monitoring.outputs.logAnalyticsId
  }
}

// --- 出力 ---
output vnetName string = network.outputs.vnetName
output logAnalyticsName string = monitoring.outputs.logAnalyticsName
