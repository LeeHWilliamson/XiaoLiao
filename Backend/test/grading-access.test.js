import test from "node:test";
import assert from "node:assert/strict";
import worker from "../src/worker.js";
import { runtime, TOKEN } from "./support.js";

const GRADING = "a-separate-grading-code-with-at-least-32-characters";
const defaults = { tone: "casual", vocabulary: "medium", replyLength: "medium" };
function request(path, token = GRADING, body = {}) {
  return new Request(`https://test.invalid${path}`, { method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(body) });
}
function chat() {
  return { requestID: crypto.randomUUID(), conversationID: crypto.randomUUID(),
    prompt: "Practice ordering tea", settings: defaults, messages: [], kind: "partner", replyToMessageID: null };
}

test("grading validation checks only its separate credential and never calls paid services", async t => {
  t.mock.method(globalThis, "fetch", async () => { throw new Error("Must not call a provider"); });
  const env = { XIAOLIAO_GRADING_TOKEN: GRADING };
  assert.equal((await worker.fetch(request("/v1/access/check"), { ...env, XIAOLIAO_CLIENT_TOKEN: GRADING })).status, 503);
  assert.equal((await worker.fetch(request("/v1/access/check"), { ...env, OPENAI_API_KEY: GRADING })).status, 503);
  const valid = await worker.fetch(request("/v1/access/check"), env);
  assert.equal(valid.status, 200);
  assert.deepEqual(await valid.json(), { status: "ok" });
  assert.equal(valid.headers.get("Cache-Control"), "no-store");
  for (const code of ["", "invalid", TOKEN, GRADING + "x"]) {
    const denied = await worker.fetch(request("/v1/access/check", code), env);
    assert.equal(denied.status, 401);
    assert.equal((await denied.json()).error.code, "invalid_grading_access");
  }
});

test("missing/malformed grading configuration fails closed; methods and bodies are checked", async () => {
  for (const code of [undefined, "short", "a".repeat(257), "a".repeat(31) + " ", GRADING + "\n", "汉".repeat(32)]) {
    assert.equal((await worker.fetch(request("/v1/access/check"), { XIAOLIAO_GRADING_TOKEN: code })).status, 503);
  }
  const env = { XIAOLIAO_GRADING_TOKEN: GRADING };
  assert.equal((await worker.fetch(new Request("https://test.invalid/v1/access/check"), env)).status, 405);
  for (const body of [[], null, { token: GRADING }]) {
    assert.equal((await worker.fetch(request("/v1/access/check", GRADING, body), env)).status, 400);
  }
  const wrongType = request("/v1/access/check");
  wrongType.headers.set("Content-Type", "text/plain");
  assert.equal((await worker.fetch(wrongType, env)).status, 415);
});

test("grading chat uses the existing global quota/cache; developer access still works", async t => {
  let calls = 0;
  t.mock.method(globalThis, "fetch", async () => {
    calls++;
    return Response.json({ status: "completed", output: [{ type: "message", role: "assistant",
      content: [{ type: "output_text", text: JSON.stringify({ explicitSettingKeys: [], conversationAdjustments: "", text: "Hello!", settings: defaults }) }] }] });
  });
  const { env, send, storage } = runtime();
  env.XIAOLIAO_GRADING_TOKEN = GRADING;
  const body = chat();
  assert.equal((await send(request("/v1/conversations/respond", GRADING, body))).status, 200);
  assert.equal((await send(request("/v1/conversations/respond", TOKEN, body))).status, 200);
  assert.equal(calls, 1);
  const before = await storage.get("limits");
  for (let i = 0; i < 15; i++) assert.equal((await send(request("/v1/access/check"))).status, 200);
  assert.deepEqual(await storage.get("limits"), before);
  for (let i = 0; i < 9; i++) assert.equal((await send(request("/v1/conversations/respond", i % 2 ? TOKEN : GRADING, chat()))).status, 200);
  assert.equal((await send(request("/v1/conversations/respond", GRADING, chat()))).status, 429);
  assert.equal((await send(request("/v1/conversations/respond", TOKEN, chat()))).status, 429);
});

test("revoking grading access blocks even cached replies without affecting developer access", async t => {
  t.mock.method(globalThis, "fetch", async () => Response.json({ status: "completed", output: [{ type: "message", role: "assistant",
    content: [{ type: "output_text", text: JSON.stringify({ explicitSettingKeys: [], conversationAdjustments: "", text: "Hello!", settings: defaults }) }] }] }));
  const { env, send } = runtime();
  env.XIAOLIAO_GRADING_TOKEN = GRADING;
  const body = chat();
  assert.equal((await send(request("/v1/conversations/respond", GRADING, body))).status, 200);
  env.XIAOLIAO_GRADING_TOKEN = GRADING + "-rotated";
  assert.equal((await send(request("/v1/access/check"))).status, 401);
  assert.equal((await send(request("/v1/conversations/respond", GRADING, body))).status, 401);
  assert.equal((await send(request("/v1/conversations/respond", TOKEN, body))).status, 200);
  delete env.XIAOLIAO_GRADING_TOKEN;
  assert.equal((await send(request("/v1/conversations/respond", GRADING, body))).status, 401);
  assert.equal((await send(request("/v1/conversations/respond", TOKEN, body))).status, 200);
});

test("grading-only deployments can authenticate chat and grammar; absent grading tokens cannot bypass auth", async () => {
  const { env, send } = runtime();
  delete env.XIAOLIAO_CLIENT_TOKEN;
  env.XIAOLIAO_GRADING_TOKEN = GRADING;
  // Invalid payloads reach their validator only with authorized grading access.
  assert.equal((await send(request("/v1/conversations/respond"))).status, 400);
  assert.equal((await send(request("/v1/grammar/evaluate"))).status, 400);
  assert.equal((await send(request("/v1/grammar/evaluate", "wrong"))).status, 401);
  env.XIAOLIAO_GRADING_TOKEN = "too-short";
  assert.equal((await send(request("/v1/grammar/evaluate", "too-short"))).status, 503);
});
