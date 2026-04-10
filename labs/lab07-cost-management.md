# Lab 07: コスト管理・最適化

> **所要時間**: 30分  
> **対応する要件**: 3.3 システム規模 (コスト管理)  
> **前提**: 各Lab でリソースが作成済み

---

## この Lab で学ぶこと

| 要件定義書の記載 | Azure での実装 |
|------------------|---------------|
| コスト超過を防止する監視・アラートの仕組み | **Azure Cost Management + 予算アラート** |
| ダッシュボード等による状況の可視化 | **コスト分析ビュー** |
| リソース利用状況に基づいたリソース見直し | **Azure Advisor 推奨事項** |
| マネージドサービスを活用しコスト削減を継続的に図る | **サーバレス / 従量課金の活用** |
| リザーブドインスタンス、スポットインスタンス等の検討 | **Azure Reservations / Savings Plans** |

---

## アジェンダ

- [Step 1: 現在のコストを確認](#step-1-現在のコストを確認)
- [Step 2: 予算アラートの設定](#step-2-予算アラートの設定)
- [Step 3: Azure Advisor でコスト最適化推奨を確認](#step-3-azure-advisor-でコスト最適化推奨を確認)
- [Step 4: リソースのタグ付けによるコスト管理](#step-4-リソースのタグ付けによるコスト管理)
- [Step 5: コスト最適化のベストプラクティス確認](#step-5-コスト最適化のベストプラクティス確認)
- [Step 6: ポータルでコスト分析を確認](#step-6-ポータルでコスト分析を確認)
- [理解度チェック](#理解度チェック)

---

## Step 1: 現在のコストを確認

```bash
# リソースグループのコスト概要を確認
az consumption usage list \
  --query "[?contains(instanceName, '${PREFIX}')].{name:instanceName, cost:pretaxCost, currency:currency}" \
  -o table 2>/dev/null || echo "コストデータは翌日以降に反映されます"

# リソースグループ内のリソース一覧 (課金対象の確認)
az resource list \
  --resource-group $RG_NAME \
  --query "[].{name:name, type:type, sku:sku.name}" \
  -o table
```

## Step 2: 予算アラートの設定

要件: 「コスト超過することがないよう、閾値を超えた場合のアラート処理等の仕組みを設けること」

```bash
# 月次予算の作成 (例: 10,000円 ≒ $70)
# 要件: 利用予定範囲（コスト）を超過しないよう監視
az consumption budget create \
  --budget-name "budget-handson-v4" \
  --resource-group $RG_NAME \
  --amount 70 \
  --category cost \
  --time-grain monthly \
  --start-date "$(date +%Y-%m)-01" \
  --end-date "2027-03-31" \
  --notifications "{
    \"Actual_GreaterThan_80_Percent\": {
      \"enabled\": true,
      \"operator\": \"GreaterThan\",
      \"threshold\": 80,
      \"contactEmails\": [\"ops@example.com\"],
      \"thresholdType\": \"Actual\"
    },
    \"Forecasted_GreaterThan_100_Percent\": {
      \"enabled\": true,
      \"operator\": \"GreaterThan\",
      \"threshold\": 100,
      \"contactEmails\": [\"ops@example.com\"],
      \"thresholdType\": \"Forecasted\"
    }
  }" 2>/dev/null || echo "予算作成にはポータルを使用してください"
```

### ポータルでの予算設定手順

1. Azure Portal → **Cost Management + Billing**
2. **予算** → **追加**
3. 以下を設定:
   - スコープ: `rg-handson-v4`
   - 予算名: `budget-handson-v4`
   - リセット期間: `月次`
   - 金額: `70 USD` (約10,000円)
4. アラート条件:
   - 実績が80%に達したら通知
   - 予測が100%を超えたら通知

## Step 3: Azure Advisor でコスト最適化推奨を確認

要件: 「リソース利用状況に基づいたリソース見直し」

```bash
# Advisor のコスト推奨事項を確認
az advisor recommendation list \
  --category cost \
  --query "[].{category:category, impact:impact, description:shortDescription.problem}" \
  -o table

# すべてのカテゴリの推奨事項
az advisor recommendation list \
  --query "[].{category:category, impact:impact, problem:shortDescription.problem}" \
  -o table
```

> **Advisor が提案する主なコスト最適化**:
> - 未使用リソースの削除
> - SKU のダウンサイジング
> - リザーブドインスタンスの推奨
> - 停止可能なリソースの特定

## Step 4: リソースのタグ付けによるコスト管理

要件: 「運用実績を評価し、コスト削減可能性を検討」

```bash
# リソースグループにコスト管理用タグを追加
az group update \
  --name $RG_NAME \
  --tags \
    "project=handson-v4" \
    "environment=dev" \
    "cost-center=digital-agency" \
    "owner=training-team" \
    "auto-shutdown=true"

# タグの確認
az group show --name $RG_NAME --query tags -o json
```

タグは Cost Management のフィルタに使用でき、プロジェクト別/環境別のコスト分析が可能になります。

## Step 5: コスト最適化のベストプラクティス確認

以下は要件定義書の各記載に対するAzureでの実装方針です:

### サーバレス / 従量課金の活用

```bash
# Azure Functions の課金プラン確認 (Consumption = 従量課金)
az functionapp show \
  --name "func-${PREFIX}-api" \
  --resource-group $RG_NAME \
  --query "{name:name, kind:kind, sku:sku}" -o json 2>/dev/null || echo "Functions 未作成の場合はスキップ"

# Static Web Apps の SKU 確認
az staticwebapp show \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "{name:name, sku:sku.name, defaultHostname:defaultHostname}" -o json 2>/dev/null || echo "SWA 未作成の場合はスキップ"
```

### リソースのサイジング確認

```bash
echo "=========================================="
echo "コスト最適化チェックリスト"
echo "=========================================="
echo ""
echo "[サーバレス / 従量課金]"
echo "  - Azure Functions: Consumption プラン → 実行時間のみ課金"
echo "  - Static Web Apps: Free プランあり → 開発・テストは無料"
echo ""
echo "[ストレージ最適化]"
echo "  - ライフサイクル管理: Hot → Cool → Archive 自動移行"
echo "  - GRS vs LRS: 重要度に応じて選択"
echo ""
echo "[データベース最適化]"
echo "  - Burstable (開発) vs General Purpose (本番)"
echo "  - ストレージの自動拡張を有効化し、余剰確保を回避"
echo ""
echo "[予約割引]"
echo "  - Reservations: 1年/3年の事前コミットで最大65%割引"
echo "  - Savings Plans: コンピューティング全般に適用可能"
```

## Step 6: ポータルでコスト分析を確認

```bash
echo "=========================================="
echo "Azure Portal でコスト分析を確認してください"
echo "=========================================="
echo ""
echo "1. Azure Portal → Cost Management → コスト分析"
echo "2. スコープ: rg-handson-v4"
echo "3. 以下の軸で分析:"
echo "   - サービス名別 (どのサービスにいくらかかっているか)"
echo "   - リソース別 (個別リソースのコスト)"
echo "   - タグ別 (environment=dev のコスト)"
echo "4. 「累計コスト」と「日次コスト」のグラフを確認"
```

---

## 理解度チェック

- [ ] 予算アラートの設定方法を理解した
- [ ] Azure Advisor のコスト推奨事項を確認した
- [ ] タグによるコスト分類の仕組みを理解した
- [ ] サーバレス/従量課金によるコスト最適化を理解した
- [ ] ストレージのライフサイクル管理によるコスト削減を理解した

### 要件 → Azure 実装の対応表

| 要件定義書の記載 | Azure での実装 |
|------------------|---------------|
| コスト超過防止のアラート | Azure Budgets + 予算アラート |
| ダッシュボードによる可視化 | Cost Management コスト分析 |
| リソース利用に基づく見直し | Azure Advisor コスト推奨 |
| サーバレス構成 | Functions (Consumption) + SWA (Free/Standard) |
| リザーブドインスタンス | Azure Reservations / Savings Plans |
| ライフサイクルコスト低減 | ストレージ ライフサイクル管理 (Hot→Cool→Archive) |
| コスト削減可能性を定期報告 | Cost Management + タグによる分類 |

---

## 全 Lab 完了

お疲れさまでした! 全7つの Lab を通じて、要件定義書のクラウド関連非機能要件が Azure 上でどのように実装されるかを体験しました。

### クリーンアップ

ハンズオンで作成したリソースを削除する場合:

```bash
# リソースグループごと削除 (全リソースが削除されます)
az group delete --name $RG_NAME --yes --no-wait

# サービスプリンシパルの削除
# az ad app delete --id $APP_ID

echo "リソースの削除を開始しました (完了まで数分かかります)"
```

### まとめ: 要件定義 → Azure サービス マッピング全体図

```
要件定義書                    Azure サービス
──────────────                ──────────────
IaC                      →  Bicep + Git
サーバレス Web           →  Azure Static Web Apps (Standard)
サーバレス API           →  Azure Functions (Linked Backend + マネージド ID)
WAF / L7 ロードバランサー →  Application Gateway v2 + WAF
SWA パブリックアクセス遮断  →  Private Endpoint + allowedIpRanges
マネージドDB               →  Azure Database for PostgreSQL
シークレット管理            →  Azure Key Vault
RBAC / 最小特権            →  Azure RBAC + マネージド ID
暗号化                     →  Key Vault CMK + TLS 1.2+
ネットワーク隔離            →  VNet + NSG + Private Endpoint
監視 (24/365)              →  Azure Monitor + Log Analytics
パフォーマンス監視          →  Application Insights
アラート                   →  Azure Monitor Alerts
SIEM                      →  Microsoft Sentinel
脆弱性スキャン             →  Microsoft Defender for Cloud
CI/CD                     →  SWA 組込み GitHub Actions
バックアップ               →  PostgreSQL 自動バックアップ + PITR
DR (別リージョン)           →  GRS + Geo-redundant backup
コスト管理                 →  Cost Management + Budgets + Advisor
```

**[README に戻る](../README.md)**
