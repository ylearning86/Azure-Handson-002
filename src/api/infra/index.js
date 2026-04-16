// src/api/infra/index.js
// インフラストラクチャ状態 API
// ハンズオンで構築した Azure リソースの接続状態を表示
const https = require('https');
const net = require('net');

// HTTPS エンドポイントの応答を確認 (レスポンスボディも取得)
function checkHttps(hostname, path, timeout, headers) {
  return new Promise((resolve) => {
    const options = {
      hostname,
      path,
      timeout: timeout || 5000,
      rejectUnauthorized: false,
      headers: headers || {}
    };
    const req = https.get(options, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        resolve({ reachable: true, status: res.statusCode, body });
      });
    });
    req.on('error', (err) => {
      resolve({ reachable: false, error: err.code || err.message });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve({ reachable: false, error: 'timeout' });
    });
  });
}

// TCP ソケット接続で PostgreSQL サーバーの存在を確認
function checkTcp(hostname, port, timeout) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    socket.setTimeout(timeout || 5000);
    socket.on('connect', () => {
      socket.destroy();
      resolve({ reachable: true });
    });
    socket.on('error', (err) => {
      socket.destroy();
      resolve({ reachable: false, error: err.code || err.message });
    });
    socket.on('timeout', () => {
      socket.destroy();
      resolve({ reachable: false, error: 'timeout' });
    });
    socket.connect(port, hostname);
  });
}

// Storage Account の存在判定 (レスポンスボディで判別)
function isStorageDeployed(result) {
  if (!result.reachable) return false;
  // 未作成の場合、ボディに AccountNotFound 等が含まれる
  if (result.body && result.body.includes('AccountNotFound')) return false;
  if (result.body && result.body.includes('InvalidUri')) return false;
  // HTTP 応答があり、上記エラーでなければ存在
  return true;
}

// Key Vault の存在判定 (レスポンスボディで判別)
function isKeyVaultDeployed(result) {
  if (!result.reachable) return false;
  // 未作成の場合、ボディに VaultNotFound 等が含まれる
  if (result.body && result.body.includes('VaultNotFound')) return false;
  if (result.body && result.body.includes('not found')) return false;
  // HTTP 応答があり、上記エラーでなければ存在
  return true;
}

// マネージド ID でアクセストークンを取得
function getManagedIdentityToken(resource) {
  const endpoint = process.env.IDENTITY_ENDPOINT;
  const header = process.env.IDENTITY_HEADER;
  if (!endpoint || !header) return Promise.resolve(null);

  const url = new URL(endpoint);
  url.searchParams.set('resource', resource);
  url.searchParams.set('api-version', '2019-08-01');

  return new Promise((resolve) => {
    const mod = url.protocol === 'https:' ? https : require('http');
    const req = mod.get(url.href, {
      headers: { 'X-IDENTITY-HEADER': header },
      timeout: 5000
    }, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        try {
          const data = JSON.parse(body);
          resolve(data.access_token || null);
        } catch {
          resolve(null);
        }
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

module.exports = async function (context, req) {
  // 環境変数からリソース情報を取得 (SWA App Settings で設定)
  const prefix = process.env.APP_PREFIX;
  if (!prefix) {
    context.res = {
      status: 500,
      headers: { "Content-Type": "application/json" },
      body: { error: "APP_PREFIX 環境変数が設定されていません。Functions App の App Settings に設定してください。" }
    };
    return;
  }
  const pgHost = process.env.PG_HOST || `pg-${prefix}.postgres.database.azure.com`;
  const storageHost = process.env.STORAGE_HOST || `${prefix}backup.blob.core.windows.net`;
  const kvHost = process.env.KV_HOST || `kv-${prefix}.vault.azure.net`;

  // マネージド ID でアクセストークンを取得 (並列)
  const [kvToken, storageToken] = await Promise.all([
    getManagedIdentityToken('https://vault.azure.net'),
    getManagedIdentityToken('https://storage.azure.com'),
  ]);

  // 各リソースの到達性を並列チェック (HTTP/TCP 接続で実際の存在を確認)
  const kvHeaders = kvToken ? { 'Authorization': `Bearer ${kvToken}` } : {};
  const storageHeaders = storageToken
    ? { 'Authorization': `Bearer ${storageToken}`, 'x-ms-version': '2023-11-03' }
    : {};

  const [pgTcp, storageHttp, kvHttp] = await Promise.all([
    checkTcp(pgHost, 5432),
    checkHttps(storageHost, '/', 5000, storageHeaders),
    checkHttps(kvHost, '/secrets?api-version=7.4', 5000, kvHeaders),
  ]);

  // デプロイ状態と接続状態を分離して判定
  const pgDeployed = pgTcp.reachable;
  const storageDeployed = isStorageDeployed(storageHttp);
  const kvDeployed = isKeyVaultDeployed(kvHttp);

  // 接続OK = 認証レベルでアクセス可能 (HTTP 2xx/3xx)
  const pgConnected = pgTcp.reachable;
  const storageConnected = storageDeployed && storageHttp.status < 400;
  const kvConnected = kvDeployed && kvHttp.status < 400;

  const components = {
    postgresql: {
      name: `pg-${prefix}`,
      type: 'Azure Database for PostgreSQL Flexible Server',
      host: pgHost,
      deployed: pgDeployed,
      connected: pgConnected,
      detail: pgTcp.reachable ? 'TCP:5432 接続OK' : `TCP:5432 ${pgTcp.error}`,
      purpose: 'RDB (バックアップ・DR 対象)'
    },
    storage: {
      name: `${prefix}backup`,
      type: 'Azure Storage Account (GRS)',
      host: storageHost,
      deployed: storageDeployed,
      connected: storageConnected,
      detail: storageDeployed
        ? (storageConnected ? `HTTP ${storageHttp.status}` : `HTTP ${storageHttp.status} (認証未設定)`)
        : storageHttp.reachable
          ? `リソース未作成`
          : storageHttp.error,
      purpose: 'バックアップ・長期アーカイブ'
    },
    keyvault: {
      name: `kv-${prefix}`,
      type: 'Azure Key Vault',
      host: kvHost,
      deployed: kvDeployed,
      connected: kvConnected,
      detail: kvDeployed
        ? (kvConnected ? `HTTP ${kvHttp.status}` : `HTTP ${kvHttp.status} (認証未設定)`)
        : kvHttp.reachable
          ? `リソース未作成`
          : kvHttp.error,
      purpose: 'シークレット管理 (DB 接続文字列等)'
    },
    functions: {
      name: `func-${prefix}-api`,
      type: 'Azure Functions (Linked Backend)',
      deployed: true,
      connected: true,
      detail: `Node.js ${process.version} で稼働中`,
      purpose: 'サーバーレス API'
    },
    staticWebApp: {
      name: `swa-${prefix}`,
      type: 'Azure Static Web Apps',
      deployed: true,
      connected: true,
      detail: 'フロントエンド配信中',
      purpose: 'フロントエンド + CI/CD'
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
