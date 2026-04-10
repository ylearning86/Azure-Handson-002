// src/api/health/index.js
// ヘルスチェック API (要件: 死活監視用エンドポイント)
module.exports = async function (context, req) {
    context.res = {
        status: 200,
        headers: { "Content-Type": "application/json" },
        body: {
            status: "healthy",
            service: "サンプル業務システム API",
            timestamp: new Date().toISOString(),
            environment: process.env.APP_ENV || "unknown"
        }
    };
};
