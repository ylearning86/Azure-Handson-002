# Lab 05: SWA 組込み CI/CD

> **所要時間**: 30分  
> **対応する要件**: 3.2 開発方式 (CI/CD)  
> **前提**: Lab 02 完了済み、GitHub アカウント

---

## この Lab で学ぶこと

| 要件定義書の記載 | Azure での実装 |
|------------------|---------------|
| CI/CD を可能とし必要な要素一式を用意 | **SWA 組込み GitHub Actions** |
| CI/CD パイプラインにおけるセキュリティの留意点 | デプロイトークン (自動管理) |
| クラウド提供の CI/CD パイプラインと連携 | SWA が GitHub Actions ワークフローを**自動生成** |
| テスト環境で事前検証後に本番環境にリリース | SWA **プレビュー環境** (Pull Request 連携) |

---

## アジェンダ

- [SWA の CI/CD の特長](#swa-の-cicd-の特長)
- [Step 1: GitHub リポジトリの準備](#step-1-github-リポジトリの準備)
- [Step 2: SWA と GitHub リポジトリを連携](#step-2-swa-と-github-リポジトリを連携)
- [Step 3: GitHub Actions ワークフローの作成](#step-3-github-actions-ワークフローの作成)
- [Step 4: CI/CD パイプラインのテスト](#step-4-cicd-パイプラインのテスト)
- [Step 5: プレビュー環境 (Pull Request 連携)](#step-5-プレビュー環境-pull-request-連携)
- [セキュリティ補足: CI/CD パイプラインのセキュリティ](#セキュリティ補足-cicd-パイプラインのセキュリティ)
- [理解度チェック](#理解度チェック)

---

## SWA の CI/CD の特長

Static Web Apps は GitHub/Azure DevOps との**組込み CI/CD**を提供します。これは要件の「クラウド提供の CI/CD パイプラインもしくはマネージドサービスと連携」に直接対応します。

```
従来の構成 (ACA):
  コード → Docker Build → ACR Push → ACA デプロイ (すべて自前構築)

SWA の場合:
  コード → GitHub Push → SWA が自動ビルド&デプロイ (組込み)
  + PR ごとにプレビュー環境を自動作成
```

---

## Step 1: GitHub リポジトリの準備

```bash
# リポジトリを GitHub に作成・プッシュ (まだの場合)
cd /c/git/Azure-Handson-002
git init 2>/dev/null
git add .
git commit -m "handson: SWA + serverless API" 2>/dev/null

# GitHub CLI でリモートを追加 (またはブラウザで作成)
# gh repo create Azure-Handson-002 --public --source=. --remote=origin --push
```

**確認**: GitHub リポジトリにコードがプッシュされていることを確認します。

![GitHub リポジトリ](../docs/screenshots/lab05/01-github-repo.png)

## Step 2: SWA と GitHub リポジトリを連携

### 方法 A: Azure CLI + GitHub CLI で連携

```bash
# 1. SWA と GitHub リポジトリを接続
GH_TOKEN=$(gh auth token)

az staticwebapp update \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --source "https://github.com/<your-username>/Azure-Handson-002" \
  --branch main \
  --token "$GH_TOKEN"

# 2. SWA のデプロイトークンを GitHub Secrets に登録
SWA_TOKEN=$(az staticwebapp secrets list \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "properties.apiKey" -o tsv)

gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN \
  --body "$SWA_TOKEN" \
  --repo <your-username>/Azure-Handson-002

# 3. Secrets が登録されたことを確認
gh secret list --repo <your-username>/Azure-Handson-002
```

> **確認**: `gh secret list` で `AZURE_STATIC_WEB_APPS_API_TOKEN` が表示されれば OK です。
> GitHub の Settings → Secrets and variables → Actions ページでも確認できます。

> **注意**: `az staticwebapp update` の `--app-location` / `--api-location` パラメータは CLI ではサポートされません。ビルド設定はワークフロー YAML で指定します。

### 方法 B: Azure Portal で連携 (推奨)

1. Azure Portal → Static Web Apps → `swa-${PREFIX}`
2. **デプロイの管理** → **GitHub**
3. 以下を設定:
   - リポジトリ: `<your-username>/Azure-Handson-002`
   - ブランチ: `main`
   - ビルドプリセット: **Custom**
   - アプリの場所: `src/web`
   - API の場所: (空白)
   - 出力の場所: (空白)
4. **保存** → GitHub Actions ワークフローが自動生成される

**確認**: SWA 概要ページで「ソース: main (GitHub)」と表示されていれば連携成功です。

![SWA GitHub連携後の概要](../docs/screenshots/lab05/04-swa-overview.png)

## Step 3: GitHub Actions ワークフローの作成

> **注意**: Portal から GitHub 連携した場合はワークフローが自動生成されますが、CLI で連携した場合や既存 SWA の場合は手動作成が必要です。

`.github/workflows/azure-static-web-apps.yml` を作成します:

```yaml
# .github/workflows/azure-static-web-apps-<random>.yml (自動生成)
# 要件: CI/CD を可能とし必要な要素一式を用意
name: Azure Static Web Apps CI/CD

on:
  push:
    branches: [main]
  pull_request:
    types: [opened, synchronize, reopened, closed]
    branches: [main]

jobs:
  build_and_deploy_job:
    if: github.event_name == 'push' || (github.event_name == 'pull_request' && github.event.action != 'closed')
    runs-on: ubuntu-latest
    name: Build and Deploy Job
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: true

      - name: Build And Deploy
        id: builddeploy
        uses: Azure/static-web-apps-deploy@v1
        with:
          # デプロイトークン (GitHub Secrets に自動設定される)
          azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
          repo_token: ${{ secrets.GITHUB_TOKEN }}
          action: "upload"
          app_location: "src/web"     # フロントエンド
          api_location: ""              # API は Linked Backend なので空 (重要)
          output_location: ""

  # PR クローズ時にプレビュー環境を自動削除
  close_pull_request_job:
    if: github.event_name == 'pull_request' && github.event.action == 'closed'
    runs-on: ubuntu-latest
    name: Close Pull Request Job
    steps:
      - name: Close Pull Request
        uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
          action: "close"
```

**ポイント**:
- `AZURE_STATIC_WEB_APPS_API_TOKEN` は SWA が GitHub Secrets に**自動設定**
- OIDC のような追加認証設定が**不要**
- Push と Pull Request の両方に対応
- `api_location` は**空**にしてください。Lab02 で Linked Backend を構成しているため、API は単体 Functions App が処理します。`api_location` に `src/api` を指定すると SWA の Managed Functions としてデプロイされ、Linked Backend と競合します

**確認**: GitHub リポジトリの `.github/workflows/` にワークフロー YAML が登録されていることを確認します。

![GitHub ワークフロー YAML](../docs/screenshots/lab05/03b-github-workflow-yaml.png)

## Step 4: CI/CD パイプラインのテスト

まず、FQDN 経由でブラウザからアプリの現在の状態を確認しておきます。

**変更前のアプリ画面:**

![変更前の Web サイト](../docs/screenshots/lab05/04-web-before.png)

次に、ソースコードに変更を加えて push します。

```bash
cd src/web

# index.html のタイトルと説明文を変更
sed -i 's/サンプル業務システム (ハンズオン)/サンプル業務システム v2 (ハンズオン)/' index.html
sed -i 's/<h1>サンプル業務システム</<h1>サンプル業務システム v2</' index.html
sed -i 's/ハンズオン用サンプルアプリケーション/ハンズオン用サンプルアプリケーション (CI\/CD でデプロイ済み)/' index.html

git add .
git commit -m "feat: update title to v2 for CI/CD demo"
git push origin main
```

GitHub Actions タブでワークフローの実行を確認してください。

![GitHub Actions 実行結果](../docs/screenshots/lab05/03-github-actions.png)

ワークフロー完了後、ブラウザで再度アクセスし、変更が反映されていることを確認します。

**変更後のアプリ画面:**

![変更後の Web サイト](../docs/screenshots/lab05/04-web-after.png)

> **ポイント**: `git push` するだけで、ビルド・デプロイが自動実行され、数分後にはブラウザで変更を確認できます。これが SWA の組込み CI/CD の利便性です。

## Step 5: プレビュー環境 (Pull Request 連携)

要件: 「テスト環境で事前検証後に本番環境にリリース」

SWA は Pull Request ごとに**プレビュー環境を自動作成**します。

### 5-1. GitHub 画面でファイルを編集して Pull Request を作成

1. GitHub リポジトリのページを開く
2. `src/web/index.html` をクリックして開く
3. 右上の**鉛筆アイコン (Edit this file)** をクリック
4. `<title>` タグを以下のように変更:

   ```html
   <!-- 変更前 -->
   <title>サンプル業務システム v2 (ハンズオン)</title>
   <!-- 変更後 -->
   <title>サンプル業務システム v2 (プレビュー環境)</title>
   ```

5. 右上の **「Commit changes...」** をクリック
6. ダイアログで **「Create a new branch for this commit and start a pull request」** を選択
7. ブランチ名はデフォルトのままでOK (例: `patch-1`)
8. **「Propose changes」** → **「Create pull request」** をクリック

PR を作成すると、SWA の GitHub Actions ワークフローが自動実行され、**プレビュー環境が作成**されます。

```text
main ブランチ  → https://xxx.azurestaticapps.net/         (本番)
PR #1         → https://xxx-1.azurestaticapps.net/        (プレビュー)
PR #2         → https://xxx-2.azurestaticapps.net/        (プレビュー)
```

- レビュアーが**プレビュー URL で動作確認**してからマージ
- PR をクローズすると**プレビュー環境が自動削除**
- これが要件の「テスト環境で事前検証後に本番環境にリリース」に対応

### 5-2. プレビュー環境の確認


**GitHub PR 画面:**

![GitHub PR](../docs/screenshots/lab05/05-github-pr.png)

**Azure Portal の SWA 環境ブレード (Production + プレビュー環境):**

![SWA 環境](../docs/screenshots/lab05/05-swa-environments.png)


> **注意**: Lab 03 で Private Endpoint を設定済みの場合、プレビュー環境への直接アクセスは 403 になります。
> これは PE が存在する SWA ではステージング環境へのパブリックアクセスが PE 経由に強制される仕様のためです (`publicNetworkAccess=Enabled` にしても Production のみに適用され、プレビュー環境は 403 のままです)。
> プレビュー環境の動作確認は、同じ VNet 内の踏み台 VM から PE 経由でアクセスします (後述のオプション手順を参照)。

<details>
<summary><strong>(オプション) 踏み台 VM でプレビュー環境にアクセス</strong></summary>

PE 環境でプレビュー環境にアクセスするには、同じ VNet 内に踏み台 VM を作成し、PE 経由でプレビュー URL にアクセスします。AGW の設定変更が不要で、**複数 PR のプレビュー環境すべてに直接アクセス可能**です。

```text
VNet (10.0.0.0/16)
├─ snet-pe   (10.0.4.0/24)  ← PE (Production: 10.0.4.4, Preview: 10.0.4.5)
└─ snet-mgmt (10.0.3.0/24)  ← 踏み台 VM (Windows Server)
    └─ ブラウザでプレビュー URL にアクセス
```

#### 1. 踏み台 VM の作成

同じ VNet の管理用サブネットに Windows Server VM を作成します。パブリック IP は付与せず、Azure Bastion 経由でアクセスします。

```bash
# NIC を作成 (パブリック IP なし)
SUBNET_ID=$(az network vnet subnet show \
  --vnet-name "vnet-${PREFIX}-dev" \
  --name snet-mgmt \
  --resource-group $RG_NAME \
  --query id -o tsv)

az network nic create \
  --resource-group $RG_NAME \
  --name "nic-${PREFIX}-bastion" \
  --subnet "$SUBNET_ID" \
  -o none

# Windows Server VM を作成
az vm create \
  --resource-group $RG_NAME \
  --name "vm-${PREFIX}-bastion" \
  --image MicrosoftWindowsServer:WindowsServer:2022-datacenter-azure-edition:latest \
  --size Standard_D2als_v6 \
  --nics "nic-${PREFIX}-bastion" \
  --admin-username azureuser \
  --admin-password "<任意の強力なパスワード>" \
  --authentication-type password
```

> **注意**: B シリーズの VM はクォータ不足でデプロイできない場合があります。その場合は D シリーズ (`Standard_D2als_v6` など) を使用してください。

#### 2. NSG でBastion からの RDP を許可

管理用サブネットの NSG に RDP (ポート 3389) の許可ルールを追加します。

```bash
# snet-mgmt の NSG 名を確認
NSG_NAME=$(az network vnet subnet show \
  --vnet-name "vnet-${PREFIX}-dev" \
  --name snet-mgmt \
  --resource-group $RG_NAME \
  --query "networkSecurityGroup.id" -o tsv | xargs basename)

# Bastion からの RDP を許可
az network nsg rule create \
  --nsg-name "$NSG_NAME" \
  --resource-group $RG_NAME \
  --name "AllowBastionRDP" \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --source-address-prefixes "VirtualNetwork" \
  --destination-port-ranges 3389 \
  -o none
```

#### 3. Bastion で VM にログイン

1. Azure Portal → VM `vm-${PREFIX}-bastion` → **接続** → **Bastion 経由で接続**
2. ユーザー名とパスワードを入力してログイン

#### 4. プレビュー環境の PE IP を確認

```bash
# プレビュー環境の URL とPE IP を確認
az staticwebapp environment list \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "[].{buildId:buildId, hostname:hostname}" -o table

# Private DNS の A レコードから PE IP を確認
az network private-dns record-set a list \
  --resource-group $RG_NAME \
  --zone-name "privatelink.azurestaticapps.net" \
  --query "[].{name:name, ip:aRecords[0].ipv4Address}" -o table
```

#### 5. hosts ファイルを編集

VM 内で**管理者権限のメモ帳**を開き、`C:\Windows\System32\drivers\etc\hosts` にプレビュー環境の PE IP を追記します。

1. スタートメニュー → **メモ帳** を右クリック → **管理者として実行**
2. ファイル → 開く → `C:\Windows\System32\drivers\etc\hosts` (「すべてのファイル」に切り替え)
3. 末尾に以下を追記して保存:

```text
# SWA Preview Environment (PE 経由)
10.0.4.5  salmon-grass-xxx-N.eastasia.7.azurestaticapps.net
```

> `salmon-grass-xxx-N` と `10.0.4.5` は手順 4 で確認した実際の値に置き換えてください。

または、PowerShell (管理者) で追記:

```powershell
# PowerShell (管理者) で実行
Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" `
  -Value "10.0.4.5  salmon-grass-xxx-N.eastasia.7.azurestaticapps.net"
```

#### 6. ブラウザでプレビュー環境にアクセス

VM 内のブラウザ (Edge) でプレビュー環境の URL にアクセスします:

```text
https://salmon-grass-xxx-N.eastasia.7.azurestaticapps.net/
```

hosts ファイルにより PE IP に名前解決され、VNet 内から PE 経由でプレビュー環境にアクセスできます。

> **ポイント**: この方法なら AGW の設定変更が不要で、**複数 PR のプレビュー環境すべてに hosts 追記だけでアクセス可能**です。PR クローズ後は hosts から該当行を削除してください。

#### 7. クリーンアップ

プレビュー確認が不要になったら、VM を停止またはリソースごと削除してコストを抑えます。

```bash
# VM を停止 (割り当て解除 → 課金停止)
az vm deallocate \
  --resource-group $RG_NAME \
  --name "vm-${PREFIX}-bastion"

# または VM と関連リソースを削除
az vm delete \
  --resource-group $RG_NAME \
  --name "vm-${PREFIX}-bastion" \
  --yes

az network nic delete \
  --resource-group $RG_NAME \
  --name "nic-${PREFIX}-bastion"
```

</details>

---

## セキュリティ補足: CI/CD パイプラインのセキュリティ

要件: 「CI/CD パイプラインにおけるセキュリティの留意点に関する技術レポート」(DS-202)

| 観点 | SWA での対応 |
|------|-------------|
| シークレット管理 | デプロイトークンは GitHub Secrets に自動格納 |
| 最小特権 | デプロイトークンは SWA リソースのみに限定 |
| 依存部品の脆弱性 | GitHub Dependabot と連携可能 |
| ビルド環境の隔離 | GitHub Actions のエフェメラルランナーを使用 |
| 監査ログ | GitHub Actions のワークフロー実行履歴 |

---

## 理解度チェック

- [ ] SWA と GitHub リポジトリを連携した
- [ ] コードプッシュで自動ビルド・デプロイが実行されることを確認した
- [ ] Pull Request でプレビュー環境が作成される仕組みを理解した
- [ ] SWA の組込み CI/CD のセキュリティ面を理解した

### 要件 → Azure 実装の対応表

| 要件定義書の記載 | Azure での実装 |
|------------------|---------------|
| CI/CD を実現 | SWA 組込み GitHub Actions (自動生成) |
| CI/CD のセキュリティ | デプロイトークン (自動管理) |
| テスト環境で事前検証 | SWA プレビュー環境 (PR 連携) |
| クラウド提供の CI/CD と連携 | SWA ↔ GitHub 組込み連携 |
| 運用保守事業者に引継可能 | ワークフロー YAML は Git 管理 |

---

**次のステップ**: [Lab 06: バックアップ & DR](lab06-backup-dr.md)
