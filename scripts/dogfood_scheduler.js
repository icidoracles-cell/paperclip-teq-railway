/**
 * dogfood_scheduler.js — Paperclip-integrated dogfood task runner
 *
 * Runs Starcaller dogfood tasks on a schedule and reports results
 * back to Paperclip via its API (issues + comments).
 *
 * Replaces standalone dogfood_tasks.js for production Railway use.
 * Uses GeminiNativeAdapter for AI-assisted task analysis.
 */

const http = require("http");
const https = require("https");
const { join, dirname } = require("path");

let GeminiNativeAdapter;
try {
  GeminiNativeAdapter = require(join(
    process.env.GEMINI_ADAPTER_PATH || dirname(require.main.filename),
    "gemini_adapter.js"
  ));
} catch (_) {
  GeminiNativeAdapter = null;
}

const PAPERCLIP_URL =
  process.env.PAPERCLIP_INTERNAL_URL || "http://127.0.0.1:3099";
const COMPANY_ID =
  process.env.PAPERCLIP_COMPANY_ID || "b73af86e-2dbd-44ef-b896-8256291797ed";
const API_KEY = process.env.PAPERCLIP_API_KEY || "";

const TEQ_APIS = [
  { name: "AetherCast", host: "weather.starcaller.uk" },
  { name: "Stratosphere", host: "agro.starcaller.uk" },
  { name: "QuasarStream", host: "finance.starcaller.uk" },
  { name: "NebulaMetrics", host: "market.starcaller.uk" },
  { name: "Meridian", host: "geo.starcaller.uk" },
  { name: "Zenith", host: "ip.starcaller.uk" },
  { name: "NovaMail", host: "mail.starcaller.uk" },
  { name: "SentinelAuth", host: "auth.starcaller.uk" },
  { name: "NexusLink", host: "link.starcaller.uk" },
  { name: "PrismBrand", host: "logo.starcaller.uk" },
];

const AGENT_IDS = {
  monitor: process.env.MONITOR_AGENT_ID || "",
  security: process.env.SECURITY_AGENT_ID || "",
  cost: process.env.COST_AGENT_ID || "",
  docs: process.env.DOCS_AGENT_ID || "",
  build: process.env.BUILD_AGENT_ID || "",
  deploy: process.env.DEPLOY_AGENT_ID || "",
  ceo: process.env.CEO_AGENT_ID || "",
};

function httpGet(url, headers = {}) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith("https") ? https : http;
    const req = lib.get(url, { headers, timeout: 10000 }, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => resolve({ status: res.statusCode, body: data }));
    });
    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("timeout"));
    });
  });
}

function paperclipRequest(method, path, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, PAPERCLIP_URL);
    const isHttps = url.protocol === "https:";
    const lib = isHttps ? https : http;

    const options = {
      hostname: url.hostname,
      port: url.port || (isHttps ? 443 : 80),
      path: url.pathname + url.search,
      method,
      headers: {
        "Content-Type": "application/json",
        ...(API_KEY ? { Authorization: `Bearer ${API_KEY}` } : {}),
      },
    };

    const req = lib.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        try {
          resolve({ status: res.statusCode, data: JSON.parse(data) });
        } catch (_) {
          resolve({ status: res.statusCode, data });
        }
      });
    });

    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function createIssue(title, description, assigneeKey = "deploy") {
  const assigneeId = AGENT_IDS[assigneeKey] || AGENT_IDS.deploy || undefined;

  try {
    const result = await paperclipRequest(
      "POST",
      `/api/companies/${COMPANY_ID}/issues`,
      {
        title,
        description,
        status: "backlog",
        priority: "high",
        ...(assigneeId ? { assigneeAgentId: assigneeId } : {}),
      }
    );
    return result;
  } catch (e) {
    console.error(`  Failed to create issue: ${e.message}`);
    return null;
  }
}

async function addIssueComment(issueId, comment) {
  try {
    await paperclipRequest("PATCH", `/api/issues/${issueId}`, {
      comment,
      status: "done",
    });
  } catch (e) {
    console.error(`  Failed to update issue: ${e.message}`);
  }
}

async function taskHealthCheck() {
  console.log("\n=== MonitorAgent: Health Check ===\n");

  const results = [];
  for (const api of TEQ_APIS) {
    const start = Date.now();
    try {
      const res = await httpGet(`https://${api.host}/`);
      const latency = Date.now() - start;
      const healthy = res.status >= 200 && res.status < 500;
      results.push({ ...api, healthy, status: res.status, latency_ms: latency });
      console.log(
        `  ${healthy ? "OK" : "FAIL"} ${api.name}: ${res.status} (${latency}ms)`
      );
    } catch (e) {
      results.push({
        ...api,
        healthy: false,
        status: "error",
        latency_ms: Date.now() - start,
        error: e.message,
      });
      console.log(`  FAIL ${api.name}: ${e.message}`);
    }
  }

  const healthyCount = results.filter((r) => r.healthy).length;
  const unhealthy = results.filter((r) => !r.healthy);

  const summary = `Health check: ${healthyCount}/${results.length} APIs healthy\n${results
    .map(
      (r) =>
        `  ${r.healthy ? "OK" : "FAIL"} ${r.name}: ${r.status} (${r.latency_ms}ms)`
    )
    .join("\n")}`;

  console.log(`\n${summary}`);

  if (unhealthy.length > 0) {
    await createIssue(
      `API Health Alert: ${unhealthy.length} unhealthy`,
      `${unhealthy.map((u) => `${u.name}: ${u.error || u.status}`).join("\n")}\n\n${summary}`,
      "deploy"
    );
  }

  return {
    task: "health_check",
    timestamp: new Date().toISOString(),
    total: results.length,
    healthy: healthyCount,
    unhealthy: unhealthy.length,
  };
}

async function taskSecurityScan() {
  console.log("\n=== SecurityAgent: Security Header Scan ===\n");

  const securityHeaders = [
    "strict-transport-security",
    "content-security-policy",
    "x-content-type-options",
    "x-frame-options",
    "x-xss-protection",
    "referrer-policy",
  ];

  const results = [];
  for (const api of TEQ_APIS) {
    try {
      const res = await new Promise((resolve, reject) => {
        const req = https.request(
          `https://${api.host}/`,
          { method: "HEAD", timeout: 10000 },
          (res) => {
            const headers = {};
            for (const h of securityHeaders) {
              headers[h] = res.headers[h] || null;
            }
            resolve({ status: res.statusCode, headers });
          }
        );
        req.on("error", reject);
        req.on("timeout", () => {
          req.destroy();
          reject(new Error("timeout"));
        });
        req.end();
      });

      const missing = securityHeaders.filter((h) => !res.headers[h]);
      const score = Math.round(
        ((securityHeaders.length - missing.length) / securityHeaders.length) * 100
      );

      results.push({ name: api.name, score, missing });
      console.log(
        `  ${score >= 80 ? "OK" : "WARN"} ${api.name}: ${score}% (${missing.join(", ") || "none"})`
      );
    } catch (e) {
      results.push({ name: api.name, score: 0, error: e.message });
      console.log(`  ERR ${api.name}: ${e.message}`);
    }
  }

  const lowScore = results.filter((r) => r.score < 80 && !r.error);

  if (lowScore.length > 0) {
    await createIssue(
      `Security: ${lowScore.length} APIs below 80% header score`,
      lowScore
        .map((r) => `${r.name}: ${r.score}% — missing: ${r.missing.join(", ")}`)
        .join("\n"),
      "security"
    );
  }

  return {
    task: "security_scan",
    timestamp: new Date().toISOString(),
    total: results.length,
    low_score: lowScore.length,
  };
}

async function taskCostCheck() {
  console.log("\n=== CostAgent: Cost Analysis ===\n");

  const estimate = {
    railway_monthly: parseFloat(process.env.RAILWAY_MONTHLY_BUDGET || "5"),
    openrouter_monthly: parseFloat(process.env.OPENROUTER_MONTHLY_BUDGET || "20"),
    gemini_free_tier: true,
    total_estimated: 0,
  };
  estimate.total_estimated = estimate.railway_monthly + estimate.openrouter_monthly;

  console.log(`  Estimated monthly: $${estimate.total_estimated}`);

  let aiAnalysis = null;
  if (GeminiNativeAdapter) {
    try {
      const adapter = new GeminiNativeAdapter();
      const result = await adapter.generate(
        `Analyze this SRE cost structure and suggest optimizations: Railway $${estimate.railway_monthly}/mo, OpenRouter $${estimate.openrouter_monthly}/mo, Gemini free tier. Total: $${estimate.total_estimated}/mo. One paragraph.`,
        { maxTokens: 200 }
      );
      aiAnalysis = result.text;
      console.log(`  AI Analysis: ${aiAnalysis}`);
    } catch (e) {
      console.log(`  AI analysis failed: ${e.message}`);
    }
  }

  return {
    task: "cost_check",
    timestamp: new Date().toISOString(),
    estimate,
    ai_analysis: aiAnalysis,
  };
}

async function taskDocsGeneration() {
  console.log("\n=== DocsAgent: Documentation Audit ===\n");

  const results = [];
  for (const api of TEQ_APIS) {
    try {
      const res = await httpGet(`https://${api.host}/docs`);
      const hasDocs = res.status === 200;
      results.push({ name: api.name, has_docs: hasDocs });
      console.log(
        `  ${hasDocs ? "OK" : "MISSING"} ${api.name}: ${hasDocs ? "docs available" : "needs documentation"}`
      );
    } catch (e) {
      results.push({ name: api.name, has_docs: false, error: e.message });
      console.log(`  ERR ${api.name}: ${e.message}`);
    }
  }

  const missingDocs = results.filter((r) => !r.has_docs);

  if (missingDocs.length > 0) {
    await createIssue(
      `Documentation: ${missingDocs.length} APIs missing docs`,
      missingDocs.map((r) => r.name).join(", "),
      "docs"
    );
  }

  return {
    task: "docs_generation",
    timestamp: new Date().toISOString(),
    total: results.length,
    missing: missingDocs.length,
  };
}

const TASKS = {
  health_check: taskHealthCheck,
  security_scan: taskSecurityScan,
  cost_check: taskCostCheck,
  docs_generation: taskDocsGeneration,
};

const SCHEDULES = {
  health_check: 5 * 60 * 1000,
  security_scan: 24 * 60 * 60 * 1000,
  cost_check: 24 * 60 * 60 * 1000,
  docs_generation: 7 * 24 * 60 * 60 * 1000,
};

async function runAllTasks() {
  console.log(`\n[${new Date().toISOString()}] Running all dogfood tasks...`);

  const results = {};
  for (const [id, fn] of Object.entries(TASKS)) {
    try {
      results[id] = await fn();
    } catch (e) {
      results[id] = { task: id, error: e.message };
      console.error(`  Task ${id} failed: ${e.message}`);
    }
  }

  return results;
}

function startScheduler() {
  console.log("Starcaller Dogfood Scheduler starting...");
  console.log("Schedules:");
  for (const [id, interval] of Object.entries(SCHEDULES)) {
    const mins = interval / 60000;
    console.log(`  ${id}: every ${mins >= 60 ? `${mins / 60}h` : `${mins}m`}`);
  }
  console.log("");

  runAllTasks();

  for (const [id, interval] of Object.entries(SCHEDULES)) {
    setInterval(async () => {
      try {
        await TASKS[id]();
      } catch (e) {
        console.error(`Scheduled task ${id} failed: ${e.message}`);
      }
    }, interval);
  }
}

if (require.main === module) {
  const args = process.argv.slice(2);

  if (args.includes("--all")) {
    runAllTasks().then((r) => console.log(JSON.stringify(r, null, 2)));
  } else if (args.includes("--schedule")) {
    startScheduler();
  } else if (args.includes("--task")) {
    const idx = args.indexOf("--task");
    const taskId = args[idx + 1];
    if (!taskId || !TASKS[taskId]) {
      console.error(`Unknown task. Available: ${Object.keys(TASKS).join(", ")}`);
      process.exit(1);
    }
    TASKS[taskId]()
      .then((r) => console.log(JSON.stringify(r, null, 2)))
      .catch((e) => {
        console.error(e.message);
        process.exit(1);
      });
  } else {
    console.log("Usage:");
    console.log("  node dogfood_scheduler.js --all           Run all tasks once");
    console.log("  node dogfood_scheduler.js --schedule      Run on schedule");
    console.log("  node dogfood_scheduler.js --task <id>     Run specific task");
    console.log(`Available tasks: ${Object.keys(TASKS).join(", ")}`);
  }
}

module.exports = {
  TASKS,
  SCHEDULES,
  startScheduler,
  runAllTasks,
  taskHealthCheck,
  taskSecurityScan,
  taskCostCheck,
  taskDocsGeneration,
};
