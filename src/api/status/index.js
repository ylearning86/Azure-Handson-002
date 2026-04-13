// src/api/status/index.js
// システムステータス API (認証必要)
module.exports = async function (context, req) {
    const prefix = process.env.APP_PREFIX || 'sampleapp542';
    context.res = {
        status: 200,
        headers: { "Content-Type": "application/json" },
        body: {
            service: "サンプル業務システム",
            version: "v1.1",
            environment: process.env.APP_ENV || "production",
            timestamp: new Date().toISOString(),
            uptime: process.uptime(),
            runtime: `Node.js ${process.version}`,
            components: {
                frontend: "Azure Static Web Apps (swa-" + prefix + ")",
                api: "Azure Functions (func-" + prefix + "-api)",
                database: "PostgreSQL Flexible Server (pg-" + prefix + ")",
                storage: "Storage Account GRS (" + prefix + "backup)",
                secrets: "Key Vault (kv-" + prefix + ")",
                gateway: "Application Gateway + WAF (agw-" + prefix + ")",
                monitoring: "Application Insights + Log Analytics"
            }
        }
    };
};
