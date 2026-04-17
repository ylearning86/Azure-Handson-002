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
> プレビュー環境の動作確認は Application Gateway 経由で行います (後述のオプション手順を参照)。

<details>
<summary><strong>(オプション) AGW パスベースルーティングでプレビュー環境にアクセス</strong></summary>

> **難易度: 高** — AGW のルーティングルールを Basic から PathBasedRouting に変更するには、**ルールの削除・再作成**が必要です。既存の Basic ルールを直接 PathBasedRouting に変更することはできない場合があるため、十分注意して実施してください。

PE 環境でプレビュー環境にアクセスするには、AGW にパスベースルーティングを構成し、`/preview/*` パスをプレビュー環境の PE IP にルーティングします。これにより Production と Preview を**同時にアクセス可能**にでき、本番環境に影響を与えません。

```text
AGW
├─ /* (デフォルト)     → Production PE IP  + Production ホストヘッダー
└─ /preview/*         → Preview PE IP     + Preview ホストヘッダー
    └─ Rewrite: /preview/xxx → /xxx
```

#### 1. プレビュー環境の PE IP を確認

```bash
# Private DNS ゾーンの A レコードから Preview の PE IP を確認
az network private-dns record-set a list \
  --resource-group $RG_NAME \
  --zone-name "privatelink.azurestaticapps.net" \
  --query "[].{name:name, ip:aRecords[0].ipv4Address}" -o table

# 出力例:
# Name                                     Ip
# ---------------------------------------  ---------
# salmon-grass-xxx.7                       10.0.4.4   ← Production
# salmon-grass-xxx-1.eastasia.7            10.0.4.5   ← Preview
```

#### 2. Preview 用バックエンドプールと HTTP 設定を作成

```bash
# Preview 環境のホスト名を変数に設定
PREVIEW_HOSTNAME=$(az staticwebapp environment list \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "[?buildId=='1'].hostname" -o tsv)

PREVIEW_PE_IP="10.0.4.5"  # 手順 1 で確認した Preview の PE IP

# Preview 用バックエンドプール
az network application-gateway address-pool create \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "previewBackendPool" \
  --servers $PREVIEW_PE_IP \
  -o none

# Preview 用 HTTP 設定 (ホストヘッダーを Preview 環境に設定)
az network application-gateway http-settings create \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "previewBackendHttpSettings" \
  --port 443 \
  --protocol Https \
  --host-name "$PREVIEW_HOSTNAME" \
  -o none
```

#### 3. URL パスマップとリライトルールを作成

```bash
# URL パスマップ: /preview/* → Preview, それ以外 → Production
az network application-gateway url-path-map create \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "pathMap" \
  --paths "/preview/*" \
  --rule-name "previewRule" \
  --address-pool "previewBackendPool" \
  --http-settings "previewBackendHttpSettings" \
  --default-address-pool "appGatewayBackendPool" \
  --default-http-settings "appGatewayBackendHttpSettings" \
  -o none

# リライトルールセットを作成
az network application-gateway rewrite-rule set create \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "previewRewriteSet" \
  -o none

# リライトルール: /preview/xxx → /xxx にパスを書き換え
az network application-gateway rewrite-rule create \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --rule-set-name "previewRewriteSet" \
  --name "stripPreviewPrefix" \
  --sequence 100 \
  --modified-path "/{var_uri_path_1}" \
  --enable-reroute true \
  --conditions "[{\"variable\":\"var_uri_path\",\"pattern\":\"/preview/(.*)\",\"ignore-case\":true,\"negate\":false}]" \
  -o none

# リライトルールセットを URL パスマップの preview ルールに関連付け
az network application-gateway url-path-map rule create \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --path-map-name "pathMap" \
  --name "previewRule" \
  --paths "/preview/*" \
  --address-pool "previewBackendPool" \
  --http-settings "previewBackendHttpSettings" \
  --rewrite-rule-set "previewRewriteSet" \
  -o none
```

#### 4. HTTPS ルールを PathBasedRouting に変更

```bash
# HTTPS ルールを PathBasedRouting に変更し、URL パスマップを関連付け
# ※ Basic → PathBasedRouting への変更ができない場合はルールを削除して再作成
az network application-gateway rule update \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "httpsRule" \
  --rule-type PathBasedRouting \
  --url-path-map "pathMap" \
  -o none
```

#### 5. 動作確認

```bash
# Production (デフォルトパス)
curl -sk -o /dev/null -w "Production: %{http_code}\n" \
  "https://${PREFIX}.japaneast.cloudapp.azure.com/"

# Preview (パスベースルーティング)
curl -sk -o /dev/null -w "Preview: %{http_code}\n" \
  "https://${PREFIX}.japaneast.cloudapp.azure.com/preview/"

# Preview API (リライトにより /preview/api/status → /api/status)
curl -sk "https://${PREFIX}.japaneast.cloudapp.azure.com/preview/api/status" | head -5
```

> **ポイント**: パスベースルーティングにより、Production と Preview が**同じ AGW FQDN で同時にアクセス可能**です。本番環境のバックエンドを切り替える必要がないため、ユーザーへの影響がありません。

#### 6. クリーンアップ (PR クローズ後)

PR をクローズまたはマージすると、SWA 側のプレビュー環境は自動削除されますが、**AGW 側の設定は残ったまま**です。プレビュー環境が削除された後も AGW の `/preview/*` パスにアクセスすると、SWA が Production のコンテンツをフォールバックで返すため 200 が返ります。

不要になった AGW のプレビュー用設定は手動で削除してください:

```bash
# 1. HTTPS ルールを Basic に戻す
az network application-gateway rule update \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "httpsRule" \
  --rule-type Basic \
  --address-pool "appGatewayBackendPool" \
  --http-settings "appGatewayBackendHttpSettings" \
  --url-path-map "" \
  -o none

# 2. URL パスマップを削除
az network application-gateway url-path-map delete \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "pathMap" \
  -o none

# 3. リライトルールセットを削除
az network application-gateway rewrite-rule set delete \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "previewRewriteSet" \
  -o none

# 4. Preview 用バックエンドプールと HTTP 設定を削除
az network application-gateway address-pool delete \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "previewBackendPool" \
  -o none

az network application-gateway http-settings delete \
  --gateway-name "agw-${PREFIX}" \
  --resource-group $RG_NAME \
  --name "previewBackendHttpSettings" \
  -o none
```

> **注意**: 実運用では、PR クローズ時に AGW のプレビュー用設定も自動削除するよう CI/CD パイプラインで自動化することを推奨します。

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
