// src/api/infra/index.js
// インフラストラクチャ状態 API
// ハンズオンで構築した Azure リソースの接続状態を表示
const dns = require('dns');
const https = require('https');

// DNS 解決でホストの到達性を確認
function checkDns(hostname) {
  return new Promise((resolve) => {
    dns.resolve4(hostname, (err, addresses) => {
      if (err) {
        resolve({ reachable: false, error: err.code });
      } else {
        resolve({ reachable: true, addresses });
      }
    });
  });
}

// HTTPS エンドポイントの応答を確認
function checkHttps(hostname, path) {
  return new Promise((resolve) => {
    const req = https.get({ hostname, path, timeout: 5000, rejectUnauthorized: false }, (res) => {
      resolve({ status: res.statusCode, reachable: true });
    });
    req.on('error', (err) => {
      resolve({ reachable: false, error: err.message });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve({ reachable: false, error: 'timeout' });
    });
  });
}

module.exports = async function (context, req) {
  // 環境変数からリソース情報を取得 (SWA App Settings で設定)
  const prefix = process.env.APP_PREFIX || 'sampleapp542';
  const pgHost = process.env.PG_HOST || `pg-${prefix}.postgres.database.azure.com`;
  const storageHost = process.env.STORAGE_HOST || `${prefix}backup.blob.core.windows.net`;
  const kvHost = process.env.KV_HOST || `kv-${prefix}.vault.azure.net`;

  // 各リソースの到達性を並列チェック
  const [pgDns, storageDns, kvDns, storageHttp] = await Promise.all([
    checkDns(pgHost),
    checkDns(storageHost),
    checkDns(kvHost),
    checkHttps(storageHost, '/'),
  ]);

  const components = {
    postgresql: {
      name: `pg-${prefix}`,
      type: 'Azure Database for PostgreSQL Flexible Server',
      host: pgHost,
      dns: pgDns.reachable ? 'resolved' : 'unreachable',
      purpose: 'RDB (バックアップ・DR 対象)',
      labs: ['Lab06']
    },
    storage: {
      name: `${prefix}backup`,
      type: 'Azure Storage Account (GRS)',
      host: storageHost,
      dns: storageDns.reachable ? 'resolved' : 'unreachable',
      http: storageHttp.reachable ? `HTTP ${storageHttp.status}` : 'unreachable',
      purpose: 'バックアップ・長期アーカイブ',
      labs: ['Lab06']
    },
    keyvault: {
      name: `kv-${prefix}`,
      type: 'Azure Key Vault',
      host: kvHost,
      dns: kvDns.reachable ? 'resolved' : 'unreachable',
      purpose: 'シークレット管理 (DB 接続文字列等)',
      labs: ['Lab03']
    },
    functions: {
      name: `func-${prefix}-api`,
      type: 'Azure Functions (Linked Backend)',
      status: 'running',
      runtime: `Node.js ${process.version}`,
      purpose: 'サーバーレス API',
      labs: ['Lab02']
    },
    staticWebApp: {
      name: `swa-${prefix}`,
      type: 'Azure Static Web Apps',
      status: 'deployed',
      purpose: 'フロントエンド + CI/CD',
      labs: ['Lab02', 'Lab05']
    }
  };

  context.res = {
    status: 200,
    headers: { "Content-Type": "application/json" },
    body: {
      service: "サンプル業務システム - インフラダッシュボード",
      timestamp: new Date().toISOString(),
      environment: process.env.APP_ENV || "production",
      components
    }
  };
};
