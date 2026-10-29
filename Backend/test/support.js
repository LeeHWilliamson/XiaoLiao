import worker, { ConversationGateway } from "../src/worker.js";
export const TOKEN = "a-private-beta-token-with-at-least-32-characters";

// Exercise the exported Worker and Durable Object with deterministic native-API doubles.
// No OpenAI requests, credentials, Cloudflare account, or npm dependencies are used.
export class MemoryStorage {
  values = new Map();
  alarmTime = null;
  queue = Promise.resolve();
  async get(key) { return structuredClone(this.values.get(key)); }
  async put(key, value) { this.values.set(key, structuredClone(value)); }
  async delete(keys) { for (const key of Array.isArray(keys) ? keys : [keys]) this.values.delete(key); }
  async getAlarm() { return this.alarmTime; }
  async setAlarm(value) { this.alarmTime = value; }
  async list({ prefix }) { return new Map([...this.values].filter(([key]) => key.startsWith(prefix))); }
  async transaction(callback) {
    const result = this.queue.then(async () => {
      const before = structuredClone(this.values);
      try { return await callback(this); }
      catch (error) { this.values = before; throw error; }
    });
    this.queue = result.catch(() => {});
    return result;
  }
}
export function runtime() {
  const storage = new MemoryStorage();
  const env = { OPENAI_API_KEY: "server-only-test-key", XIAOLIAO_CLIENT_TOKEN: TOKEN, OPENAI_MODEL: "gpt-6.1-terra" };
  const gateway = new ConversationGateway({ storage }, env);
  env.CHAT_GATEWAY = { idFromName: name => name, get: () => gateway };
  return { storage, gateway, env, send: request => worker.fetch(request, env) };
}

