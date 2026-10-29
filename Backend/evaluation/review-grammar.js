// Explicit opt-in: one selected public reference sentence, one authenticated API request.
// No requests on --list. Never prints the beta token. Requires Node 22+.
import { readFile } from "node:fs/promises";
const cases = JSON.parse(await readFile(new URL("./grammar-cases.json", import.meta.url), "utf8"));
const selected = process.argv[2];
if (selected === "--list") {
  for (const item of cases) console.log(`${item.id}: ${item.text}`);
} else {
  try {
    const item = cases.find(item => item.id === (selected || "agreement-error"));
    if (!item) throw new Error("Unknown case. Run with --list to see case IDs.");
    const token = process.env.XIAOLIAO_EVAL_TOKEN;
    if (!token || token.length < 32) throw new Error("Set XIAOLIAO_EVAL_TOKEN locally to your beta access token first.");
    const url = new URL("/v1/grammar/evaluate", process.env.XIAOLIAO_EVAL_URL || "https://xiaoliao-api.leeharriswilliamson.workers.dev");
    if (url.protocol !== "https:" || url.username || url.password) throw new Error("Use an HTTPS Worker URL without credentials.");
    const request = { requestID: crypto.randomUUID(), conversationID: crypto.randomUUID(), messageID: crypto.randomUUID(),
      messageRevision: 1, textSource: "messageText", text: item.text, rubricVersion: "grammar-v1" };
    const response = await fetch(url, { method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(request), signal: AbortSignal.timeout(50_000) });
    const result = await response.json();
    if (!response.ok) throw new Error(`HTTP ${response.status}: ${result.error?.code || "service_error"}`);
    if (result.requestID !== request.requestID || !Array.isArray(result.opportunities)) throw new Error("Invalid response identity/shape.");
    const matches = (expected, actual) => (!expected.categoryID || actual.category.categoryID === expected.categoryID)
      && (!expected.evidence || actual.originalText === expected.evidence) && actual.outcome === expected.outcome;
    const missing = item.required.filter(expected => !result.opportunities.some(actual => matches(expected, actual)));
    const unexpected = result.opportunities.filter(actual => item.forbidden.some(expected => matches(expected, actual)));
    console.log(JSON.stringify({ caseID: item.id, text: item.text, passed: missing.length === 0 && unexpected.length === 0,
      missingRequired: missing, unexpected, model: result.model, rubricVersion: result.rubricVersion,
      opportunities: result.opportunities }, null, 2));
    if (missing.length || unexpected.length) process.exitCode = 1;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
