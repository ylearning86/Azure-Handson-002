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

## Step 2: SWA と GitHub リポジトリを連携

SWA を GitHub リポジトリに接続すると、GitHub Actions ワークフローが **自動生成**されます。

### 方法 A: Azure CLI で連携

```bash
# GitHub のパーソナルアクセストークンを設定
# https://github.com/settings/tokens で "repo" と "workflow" スコープのトークンを作成
# export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

# SWA と GitHub リポジトリを連携
az staticwebapp update \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --source "https://github.com/<your-username>/Azure-Handson-002" \
  --branch main \
  --app-location "src/web" \
  --api-location "src/api" \
  --token "$GITHUB_TOKEN"
```

### 方法 B: Azure Portal で連携 (推奨)

1. Azure Portal → Static Web Apps → `swa-${PREFIX}`
2. **デプロイの管理** → **GitHub**
3. 以下を設定:
   - リポジトリ: `<your-username>/Azure-Handson-002`
   - ブランチ: `main`
   - ビルドプリセット: **Custom**
   - アプリの場所: `src/web`
   - API の場所: `src/api`
   - 出力の場所: (空白)
4. **保存** → GitHub Actions ワークフローが自動生成される

## Step 3: 自動生成されたワークフローの確認

SWA は `.github/workflows/` に以下のようなワークフローを自動生成します:

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
          api_location: "src/api"     # Functions API
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

## Step 4: CI/CD パイプラインのテスト

```bash
# ソースコードに変更を加えてプッシュ
cd src/web

# index.html の title を変更 (例)
# git add . && git commit -m "feat: update title" && git push
```

GitHub Actions タブでワークフローの実行を確認してください。

## Step 5: プレビュー環境 (Pull Request 連携)

要件: 「テスト環境で事前検証後に本番環境にリリース」

SWA は Pull Request ごとに**プレビュー環境を自動作成**します。

```bash
# 新しいブランチで変更
git checkout -b feature/update-status-api

# src/api/status/index.js を変更
# git add . && git commit -m "feat: add uptime to status API"
# git push origin feature/update-status-api

# GitHub で Pull Request を作成
# → SWA がプレビュー環境を自動作成
# → PR コメントにプレビュー URL が投稿される
```

```
main ブランチ  → https://xxx.azurestaticapps.net/         (本番)
PR #1         → https://xxx-1.azurestaticapps.net/        (プレビュー)
PR #2         → https://xxx-2.azurestaticapps.net/        (プレビュー)
```

- レビュアーが**プレビュー URL で動作確認**してからマージ
- PR をクローズすると**プレビュー環境が自動削除**
- これが要件の「テスト環境で事前検証後に本番環境にリリース」に対応

## Step 6: デプロイ状況の確認

```bash
# SWA のデプロイ履歴
az staticwebapp show \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "{name:name, defaultHostname:defaultHostname, branch:branch}" -o json

# 現在の URL
SWA_URL=$(az staticwebapp show \
  --name "swa-${PREFIX}" \
  --resource-group $RG_NAME \
  --query "defaultHostname" -o tsv)

echo "本番 URL: https://${SWA_URL}"
curl -s "https://${SWA_URL}/api/health" | python -m json.tool
```

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
