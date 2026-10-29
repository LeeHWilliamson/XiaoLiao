export class APIError extends Error {
  constructor(status, code, message, retryable = false) {
    super(message);
    Object.assign(this, { status, code, retryable });
  }
}

// Shared native Responses transport. Callers validate their own strict output contract.
export async function requestModelJSON(requestID, body, env, fetcher = fetch) {
  let response;
  try {
    response = await fetcher("https://api.openai.com/v1/responses", {
      method: "POST", headers: { "Authorization": `Bearer ${env.OPENAI_API_KEY}`, "Content-Type": "application/json",
        "X-Client-Request-Id": requestID },
      body: JSON.stringify(body), signal: AbortSignal.timeout(35_000)
    });
  } catch { throw new APIError(504, "provider_timeout", "AI 服务暂未返回结果，请稍后重试。", true); }
  if (!response.ok) {
    const busy = response.status === 429;
    throw new APIError(503, busy ? "provider_busy" : "provider_unavailable",
      busy ? "AI 服务繁忙，请稍后重试。" : "AI 服务暂不可用，请稍后重试。", true);
  }
  try {
    const value = await response.json();
    if (value.status !== "completed" || !Array.isArray(value.output)) throw new Error();
    const contents = value.output.filter(item => item.type === "message" && item.role === "assistant")
      .flatMap(item => item.content ?? []);
    if (contents.some(item => item.type === "refusal")) throw new APIError(422, "refused", "暂时无法处理这条消息。请调整内容。");
    return JSON.parse(contents.filter(item => item.type === "output_text").map(item => item.text).join(""));
  } catch (error) {
    if (error instanceof APIError) throw error;
    throw new APIError(502, "invalid_reply", "AI 返回的数据不完整，请重试。", true);
  }
}
