// infra/modules/network.bicep
// 要件: クラウド上に論理的に隔離された仮想閉域ネットワークを構築
// 要件: サブシステムごとに個別のネットワークアドレス空間を割り当て

@description('リソース名のプレフィックス')
param prefix string

@description('リソースのロケーション (要件: 日本国内リージョン)')
param location string

@description('環境名 (dev/test/prod)')
@allowed(['dev', 'test', 'prod'])
param env string

// --- NSG: アプリケーション層 ---
// 要件: 必要なポート/プロトコルのみ許可
resource nsgApp 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-${prefix}-app-${env}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowHTTPS'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --- NSG: データ層 ---
// 要件: 重要なシステムコンポーネントを他の内部要素から分離
resource nsgData 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-${prefix}-data-${env}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAppSubnet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '5432'
          sourceAddressPrefix: '10.0.1.0/24'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --- NSG: 管理層 ---
resource nsgMgmt 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-${prefix}-mgmt-${env}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'DenyAllInbound'
        properties: {
          priority: 4096
          direction: 'Inbound'
          access: 'Deny'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// --- VNet 定義 ---
// 要件: 外部/内部ネットワークを通信回線上で分離
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-${prefix}-${env}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        // Application Gateway 専用サブネット (WAF v2 に必要)
        name: 'snet-appgw'
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        name: 'snet-app'
        properties: {
          addressPrefix: '10.0.1.0/24'
          networkSecurityGroup: { id: nsgApp.id }
        }
      }
      {
        name: 'snet-data'
        properties: {
          addressPrefix: '10.0.2.0/24'
          networkSecurityGroup: { id: nsgData.id }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-mgmt'
        properties: {
          addressPrefix: '10.0.3.0/24'
          networkSecurityGroup: { id: nsgMgmt.id }
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
      {
        // Private Endpoint 用サブネット (SWA PE, Key Vault PE 等)
        name: 'snet-pe'
        properties: {
          addressPrefix: '10.0.4.0/24'
          privateEndpointNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

// --- 出力 ---
output vnetId string = vnet.id
output vnetName string = vnet.name
output snetAppGwId string = vnet.properties.subnets[0].id
output snetAppId string = vnet.properties.subnets[1].id
output snetDataId string = vnet.properties.subnets[2].id
output snetMgmtId string = vnet.properties.subnets[3].id
output snetPeId string = vnet.properties.subnets[4].id
