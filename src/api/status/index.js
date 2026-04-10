// src/api/status/index.js
// システムステータス API
module.exports = async function (context, req) {
    context.res = {
        status: 200,
        headers: { "Content-Type": "application/json" },
        body: {
            service: "サンプル業務システム",
            version: "v1.1",
            environment: process.env.APP_ENV || "unknown",
            timestamp: new Date().toISOString(),
            uptime: process.uptime(),
            components: {
                api: "running",
                frontend: "deployed"
            }
        }
    };
};
