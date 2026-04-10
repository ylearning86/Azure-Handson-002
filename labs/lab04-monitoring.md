# Lab 04: 監視・可用性・自動復旧

> **所要時間**: 45分  
> **対応する要件**: 3.5 信頼性, 3.4 性能, 3.9 継続性  
> **前提**: Lab 03 完了済み

---

## この Lab で学ぶこと

| 要件定義書の記載 | Azure での実装 |
|------------------|---------------|
| 稼働率 99.5% | **SWA グローバル分散 + Functions 自動スケール** |
| 24時間365日監視 | **Azure Monitor + Log Analytics** |
| 障害やアラートを検知し自動通知 | **Azure Monitor アラートルール** |
| ダッシュボード等による状況の可視化 | **Azure ダッシュボード + ブック** |
| 参照系 5秒以内 / 更新系 7秒以内 | **Application Insights のパフォーマンス監視** |
| 障害が発生したコンポーネントを切り離しシステム全体を停止させない | **SWA グローバル CDN + Functions 自動復旧** |

---

## Step 1: Application Insights でパフォーマンス監視を設定

要件: 「レスポンスタイムの遵守率80%以上」

```bash
# Application Insights の接続文字列を取得
APPI_CONN=$(az monitor app-insights component show \
  --app "appi-${PREFIX}-dev" \
  --resource-group $RG_NAME \
  --query "connectionString" -o tsv)

# Static Web Apps の Managed Functions に Application Insights を設定
az staticwebapp appsettings set \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --setting-names "APPLICATIONINSIGHTS_CONNECTION_STRING=$APPI_CONN"

echo "Application Insights の接続文字列を SWA に設定しました"
```

## Step 2: アラートルールの作成

要件: 「障害やアラートを検知し、重要性等で分類した上で自動で通知する仕組み」

### アラート: レスポンスタイム超過

```bash
# アクショングループの作成 (通知先)
az monitor action-group create \
  --name "ag-handson-ops" \
  --resource-group $RG_NAME \
  --short-name "ops-team" \
  --action email ops-team ops@example.com

# レスポンスタイムアラート (要件: 5秒以内)
APPI_ID=$(az monitor app-insights component show \
  --app "appi-${PREFIX}-dev" \
  --resource-group $RG_NAME \
  --query id -o tsv)

az monitor metrics alert create \
  --name "alert-response-time" \
  --resource-group $RG_NAME \
  --scopes "$APPI_ID" \
  --condition "avg requests/duration > 5000" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --description "要件: 参照系処理のレスポンスタイムが5秒を超過" \
  --action "ag-handson-ops"
```

### アラート: エラー率上昇

```bash
# HTTP 5xx エラー率アラート
az monitor metrics alert create \
  --name "alert-error-rate" \
  --resource-group $RG_NAME \
  --scopes "$APPI_ID" \
  --condition "count requests/failed > 10" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 1 \
  --description "5分間で10件以上のHTTPエラーが発生" \
  --action "ag-handson-ops"
```

## Step 3: SWA の可用性確認

要件: 「SPOF を極力排除」「障害が発生したコンポーネントを切り離し」

```bash
# SWA のデプロイ状態を確認
az staticwebapp show \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "{name:name, defaultHostname:defaultHostname, sku:sku.name}" -o json

# SWA のヘルスチェック
SWA_URL=$(az staticwebapp show \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "defaultHostname" -o tsv)

curl -s "https://${SWA_URL}/api/health" | python -m json.tool
```

> SWA はグローバルに分散された CDN でホスティングされ、単一障害点が排除されています。  
> Managed Functions もマネージド環境で自動的に復旧されます。

## Step 4: Log Analytics でクエリを実行

要件: 「操作ログやアクセスログ等のシステムログを取得・保管し出力可能」

```bash
# SWA / Functions のログをクエリ (直近30分)
az monitor log-analytics query \
  --workspace "law-${PREFIX}-dev" \
  --analytics-query "AppRequests | where TimeGenerated > ago(30m) | project TimeGenerated, Name, DurationMs, ResultCode | take 20" \
  --timespan PT30M \
  -o table 2>/dev/null || echo "ログが蓄積されるまで数分かかります"
```

### KQL クエリ例: パフォーマンス分析

Azure Portal の Log Analytics で以下のクエリを実行してみてください:

```kql
// 要件: アプリケーション処理時間の分析
// 直近1時間のリクエストレスポンスタイム分布
requests
| where timestamp > ago(1h)
| summarize
    p50 = percentile(duration, 50),
    p95 = percentile(duration, 95),
    p99 = percentile(duration, 99),
    count = count()
  by bin(timestamp, 5m)
| render timechart
```

```kql
// 要件: レスポンスタイム遵守率 (目標80%)
requests
| where timestamp > ago(1h)
| summarize
    total = count(),
    within_sla = countif(duration <= 5000)  // 5秒以内
| extend compliance_rate = round(100.0 * within_sla / total, 1)
| project total, within_sla, compliance_rate
```

## Step 5: Azure ダッシュボードの作成

要件: 「ダッシュボード等による状況の可視化」

```bash
# ダッシュボードをポータルで作成する方法:
echo "=========================================="
echo "Azure Portal でダッシュボードを作成します"
echo "=========================================="
echo ""
echo "1. Azure Portal (https://portal.azure.com) にアクセス"
echo "2. 「ダッシュボード」→「新しいダッシュボード」→「空のダッシュボード」"
echo "3. 以下のタイルを追加:"
echo "   - Application Insights → パフォーマンス (レスポンスタイム)"
echo "   - Static Web Apps → デプロイ状態"
echo "   - Log Analytics → カスタムクエリ結果"
echo "   - リソースグループ → リソース一覧"
echo "4. 「保存」をクリック"
```

## Step 6: サービス正常性アラートの設定

要件: 「クラウドサービスの機能や性能に変更が発生した場合、影響を確認」

```bash
# Azure サービス正常性アラート (Japan East リージョン)
az monitor activity-log alert create \
  --name "alert-service-health" \
  --resource-group $RG_NAME \
  --condition category=ServiceHealth \
  --action-group "ag-handson-ops" \
  --description "Azure サービスの障害・メンテナンス通知"
```

---

## 理解度チェック

- [ ] Application Insights をアプリに接続した
- [ ] レスポンスタイム超過のアラートルールを作成した
- [ ] Log Analytics で KQL クエリを実行しログを分析した
- [ ] 要件定義の「稼働率」「レスポンスタイム」がどう監視されるか理解した
- [ ] SWA のグローバル分散による可用性確保の仕組みを理解した

### 要件 → Azure 実装の対応表

| 要件定義書の記載 | Azure での実装 |
|------------------|---------------|
| 稼働率 99.5% | SWA グローバル CDN + Functions 自動復旧 + アラート |
| 24時間365日監視 | Azure Monitor + Log Analytics (常時収集) |
| レスポンスタイム監視 | Application Insights + メトリクスアラート |
| ダッシュボード可視化 | Azure ダッシュボード + Application Insights |
| 障害検知と自動通知 | アラートルール + アクショングループ |
| SPOF 排除 | ACA 複数レプリカ + ヘルスプローブ |
| クラウドサービス変更の検知 | Azure サービス正常性アラート |

---

**次のステップ**: [Lab 05: GitHub Actions CI/CD](lab05-cicd.md)
