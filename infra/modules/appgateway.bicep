// infra/modules/appgateway.bicep
// 要件: L3～L7 層で対策可能な仕組みを導入
// 要件: 不正侵入や Web 特有の攻撃への対策 (WAF)

@description('リソース名のプレフィックス')
param prefix string

@description('リソースのロケーション')
param location string

@description('環境名')
@allowed(['dev', 'test', 'prod'])
param env string

@description('Application Gateway 用サブネットの ID')
param subnetId string

@description('Log Analytics Workspace の ID (診断ログ送信先)')
param logAnalyticsId string

// --- パブリック IP ---
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-${prefix}-appgw-${env}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// --- WAF ポリシー ---
// 要件: OWASP Top 10 対応、SQLi / XSS 遮断
resource wafPolicy 'Microsoft.Network/ApplicationGatewayWebApplicationFirewallPolicies@2024-01-01' = {
  name: 'wafpol-${prefix}-${env}'
  location: location
  properties: {
    policySettings: {
      state: 'Enabled'
      // Prevention = 検知 + 遮断 (要件: 不正通信の遮断)
      mode: 'Prevention'
      requestBodyCheck: true
      maxRequestBodySizeInKb: 128
      fileUploadLimitInMb: 100
    }
    managedRules: {
      managedRuleSets: [
        {
          // 要件: OWASP Top 10 対応
          ruleSetType: 'OWASP'
          ruleSetVersion: '3.2'
        }
      ]
    }
    customRules: [
      {
        // 要件: サービス不能化の防止 (レートリミット)
        name: 'RateLimitPerIP'
        priority: 100
        ruleType: 'RateLimitRule'
        rateLimitThreshold: 100
        rateLimitDuration: 'FiveMins'
        action: 'Block'
        matchConditions: [
          {
            matchVariables: [
              {
                variableName: 'RemoteAddr'
              }
            ]
            operator: 'IPMatch'
            negationCondition: true
            matchValues: [
              '127.0.0.1'
            ]
          }
        ]
      }
    ]
  }
}

// --- Application Gateway v2 ---
resource appGateway 'Microsoft.Network/applicationGateways@2024-01-01' = {
  name: 'agw-${prefix}-${env}'
  location: location
  properties: {
    sku: {
      name: 'WAF_v2'
      tier: 'WAF_v2'
      capacity: 1
    }
    firewallPolicy: {
      id: wafPolicy.id
    }
    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: subnetId
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'defaultBackendPool'
        properties: {
          backendAddresses: []
        }
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'defaultHttpSettings'
        properties: {
          port: 80
          protocol: 'Http'
          requestTimeout: 30
          pickHostNameFromBackendAddress: true
        }
      }
    ]
    httpListeners: [
      {
        name: 'httpListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', 'agw-${prefix}-${env}', 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', 'agw-${prefix}-${env}', 'port_80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'defaultRoutingRule'
        properties: {
          priority: 100
          ruleType: 'Basic'
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', 'agw-${prefix}-${env}', 'httpListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', 'agw-${prefix}-${env}', 'defaultBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', 'agw-${prefix}-${env}', 'defaultHttpSettings')
          }
        }
      }
    ]
  }
}

// --- 診断設定 ---
// 要件: WAF ログ・アクセスログを Log Analytics に送信
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'agw-diagnostics'
  scope: appGateway
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        category: 'ApplicationGatewayAccessLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayFirewallLog'
        enabled: true
      }
      {
        category: 'ApplicationGatewayPerformanceLog'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output appGatewayId string = appGateway.id
output appGatewayName string = appGateway.name
output publicIpAddress string = publicIp.properties.ipAddress
output wafPolicyName string = wafPolicy.name
