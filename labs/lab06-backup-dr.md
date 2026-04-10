# Lab 06: バックアップ & DR (災害復旧)

> **所要時間**: 45分  
> **対応する要件**: 3.9 継続性に関する事項  
> **前提**: Lab 01 完了済み

---

## この Lab で学ぶこと

| 要件定義書の記載 | Azure での実装 |
|------------------|---------------|
| RTO: 1営業日以内 | **ゾーン冗長 + PITR** |
| RPO: 最新バックアップ / 障害時点 | **PITR (Point-in-Time Restore)** |
| バックアップ頻度: 日次 | **PostgreSQL 自動バックアップ** |
| 3-2-1 ルール、別リージョン隔地保管 | **GRS (Geo-Redundant Storage)**、**Geo-backup** |
| バックアップ保持期間: 4週間 | **バックアップリテンション設定** |
| ログ保管期間: 3年 | **Storage Account への長期アーカイブ** |
| マルチAZ冗長化 | **ゾーン冗長デプロイ** |

---

## Step 1: Azure Database for PostgreSQL Flexible Server の作成

要件: 「マネージドサービスを最大限活用」「ゾーン冗長でSPOF排除」

```bash
# PostgreSQL Flexible Server の作成
# 要件: マルチAZ冗長化、日本国内リージョン
az postgres flexible-server create \
  --name "pg-${PREFIX}" \
  --resource-group $RG_NAME \
  --location $LOCATION \
  --admin-user pgadmin \
  --admin-password "H@ndson2026!" \
  --sku-name Standard_B1ms \
  --tier Burstable \
  --storage-size 32 \
  --version 16 \
  --high-availability Disabled \
  --backup-retention 28 \
  --geo-redundant-backup Disabled \
  --yes

# ※ ハンズオン環境ではコスト節約のため HA と Geo-backup を Disabled にしています
# 本番環境では以下のように設定します:
#   --high-availability ZoneRedundant   (要件: マルチAZ)
#   --geo-redundant-backup Enabled       (要件: 別リージョン隔地保管)
#   --backup-retention 35               (要件: 4週間+α)
```

> **本番構成との対比**:
> | 設定 | ハンズオン | 本番 (要件準拠) |
> |------|-----------|---------------|
> | SKU | Burstable B1ms | General Purpose D4s+ |
> | HA | Disabled | ZoneRedundant |
> | Geo-backup | Disabled | Enabled |
> | Retention | 28日 | 35日 |

## Step 2: バックアップ設定の確認

要件: 「バックアップ頻度は原則日次」「4週間程度のデータをバックアップとして保持」

```bash
# バックアップ設定の確認
az postgres flexible-server show \
  --name "pg-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "{
    name:name,
    backupRetentionDays:backup.backupRetentionDays,
    geoRedundantBackup:backup.geoRedundantBackup,
    earliestRestoreDate:backup.earliestRestoreDate
  }" -o json
```

**PostgreSQL Flexible Server のバックアップ仕様**:
- **自動バックアップ**: フルバックアップ (週次) + 差分バックアップ + WAL アーカイブ (継続的)
- **PITR**: 直近5分前まで任意の時点に復旧可能 (要件: 「障害発生時点への復旧を可能とする」)
- **保持期間**: 7～35日 (要件: 4週間 = 28日)

## Step 3: PITR (Point-in-Time Restore) の体験

要件: 「障害発生時点への復旧を可能とする」

```bash
# テスト用データベースの作成
az postgres flexible-server db create \
  --server-name "pg-${PREFIX}" \
  --resource-group $RG_NAME \
  --database-name "sampledb"

# 現在時刻を記録 (復旧ポイントとして使用)
RESTORE_POINT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
echo "復旧ポイント: $RESTORE_POINT"

# (数分待ってから) PITR でリストア先サーバーを作成
# ※ 実際にリストアを行う場合:
echo "================================================================"
echo "PITR リストアコマンド (確認用、実行はオプション):"
echo "================================================================"
echo "az postgres flexible-server restore \\"
echo "  --name pg-${PREFIX}-restore \\"
echo "  --resource-group $RG_NAME \\"
echo "  --source-server pg-${PREFIX} \\"
echo "  --restore-time \"$RESTORE_POINT\""
echo ""
echo "※ リストアには 10-20分程度かかります"
echo "※ ハンズオンでは実行をスキップしても構いません"
```

## Step 4: Blob Storage のバックアップ (長期アーカイブ)

要件: 「文書管理規定に基づくデータは保管期間5年」「3-2-1ルール」

```bash
# ストレージアカウントの作成
# 要件: GRS (Geo-Redundant Storage) で別リージョンにレプリケーション
az storage account create \
  --name "${PREFIX}backup" \
  --resource-group $RG_NAME \
  --location $LOCATION \
  --sku Standard_GRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# バックアップ用コンテナの作成
az storage container create \
  --name "db-backups" \
  --account-name "${PREFIX}backup" \
  --auth-mode login

# アーカイブ用コンテナ (要件: 5年保管)
az storage container create \
  --name "archive" \
  --account-name "${PREFIX}backup" \
  --auth-mode login
```

### 不変ストレージポリシーの設定

要件: 「バックアップデータのバージョニング」「外部からの編集を防止」

```bash
# バージョニングの有効化 (要件: バックアップデータのバージョン管理)
az storage account blob-service-properties update \
  --account-name "${PREFIX}backup" \
  --enable-versioning true

# 論理的な削除の有効化 (要件: データの減失防止)
az storage account blob-service-properties update \
  --account-name "${PREFIX}backup" \
  --enable-delete-retention true \
  --delete-retention-days 30
```

## Step 5: ライフサイクル管理ポリシー

要件: 「ログ保管期間3年」「文書データ保管期間5年」

```bash
# ライフサイクル管理ポリシーの作成
az storage account management-policy create \
  --account-name "${PREFIX}backup" \
  --resource-group $RG_NAME \
  --policy '{
    "rules": [
      {
        "name": "archive-old-backups",
        "type": "Lifecycle",
        "definition": {
          "actions": {
            "baseBlob": {
              "tierToCool": { "daysAfterModificationGreaterThan": 30 },
              "tierToArchive": { "daysAfterModificationGreaterThan": 90 },
              "delete": { "daysAfterModificationGreaterThan": 1825 }
            }
          },
          "filters": {
            "blobTypes": ["blockBlob"],
            "prefixMatch": ["archive/"]
          }
        }
      },
      {
        "name": "delete-old-logs",
        "type": "Lifecycle",
        "definition": {
          "actions": {
            "baseBlob": {
              "tierToCool": { "daysAfterModificationGreaterThan": 30 },
              "delete": { "daysAfterModificationGreaterThan": 1095 }
            }
          },
          "filters": {
            "blobTypes": ["blockBlob"],
            "prefixMatch": ["db-backups/"]
          }
        }
      }
    ]
  }'
```

| ストレージ階層 | 期間 | コスト | 用途 |
|--------------|------|--------|------|
| Hot | 0～30日 | 高 | 直近のバックアップ |
| Cool | 30～90日 | 中 | 過去1-3か月分 |
| Archive | 90日～5年 | 低 | 長期保管 (要件: 5年) |
| 削除 | 5年超 | - | 自動削除 |

## Step 6: レプリケーション状態の確認

要件: 「遠隔地に転送したバックアップデータ」

```bash
# GRS レプリケーション状態の確認
az storage account show \
  --name "${PREFIX}backup" \
  --resource-group $RG_NAME \
  --query "{
    name:name,
    primaryLocation:primaryLocation,
    secondaryLocation:secondaryLocation,
    replication:sku.name,
    statusOfSecondary:statusOfSecondary
  }" -o json
```

出力例:
```json
{
  "name": "sampleapp123backup",
  "primaryLocation": "japaneast",
  "secondaryLocation": "japanwest",     // ← 別リージョン (要件対応)
  "replication": "Standard_GRS",
  "statusOfSecondary": "available"
}
```

---

## 理解度チェック

- [ ] PostgreSQL Flexible Server のバックアップ設定を確認した
- [ ] PITR (Point-in-Time Restore) の仕組みを理解した
- [ ] GRS による別リージョンレプリケーションを確認した
- [ ] ライフサイクル管理で Hot → Cool → Archive の自動階層化を設定した
- [ ] 要件の RTO/RPO がどのように実現されるか理解した

### 要件 → Azure 実装の対応表

| 要件定義書の記載 | Azure での実装 |
|------------------|---------------|
| RTO: 1営業日以内 | PostgreSQL ゾーン冗長 HA + PITR |
| RPO: 障害発生時点 | PostgreSQL WAL アーカイブ (PITR) |
| バックアップ日次、4週間保持 | PostgreSQL 自動バックアップ (retention=28) |
| 3-2-1 ルール、別リージョン隔地 | GRS (Japan East → Japan West) |
| ログ保管3年 | ライフサイクル管理 (1095日で削除) |
| 文書データ5年保管 | ライフサイクル管理 (Archive 階層 → 1825日で削除) |
| バックアップデータのバージョニング | Blob バージョニング有効化 |
| データ減失防止 | 論理的削除 + 不変ストレージ |

---

**次のステップ**: [Lab 07: コスト管理・最適化](lab07-cost-management.md)
