# Private-beta text conversations

The app talks to `https://xiaoliao-api.leeharriswilliamson.workers.dev`. The Worker calls OpenAI's Responses API; the OpenAI key stays in Cloudflare. History, recordings, and statistics remain on the phone. This increment sends text only and returns complete text replies, without streaming, speech recognition, synthesized speech, or grammar/clause evaluation.

## 1. Cloudflare secrets

You have already saved `OPENAI_API_KEY`. Keep it there; never paste it into chat, Swift code, an Xcode scheme, or Git.

Add one more **Secret** to the same Worker under Settings → Variables and Secrets:

| Name | Value |
| --- | --- |
| `XIAOLIAO_CLIENT_TOKEN` | A new random ASCII token of at least 32 characters, saved in your password manager. This is NOT the OpenAI key. |

The app uses this separate credential to keep the paid endpoint private during development. You will put this same beta token in your local Xcode Run environment. Do not send either secret here. The token is shared beta access, not production user authentication. Release builds deliberately have no embedded token and cannot use this beta flow; account authentication is required before public/TestFlight distribution.

## 2. Deploy the prepared Worker

On your Mac, open Terminal in the repository's `Backend` directory. Node.js 22+ is needed for local tests; a current Node LTS is suitable for Wrangler. Run these commands one at a time:

```sh
npm test
npx wrangler login
npx wrangler deploy
```

`npx` downloads Cloudflare's deployment tool and asks to install it the first time. `login` opens your browser: choose the Cloudflare account containing `xiaoliao-api`. `deploy` replaces that Worker's starter code, applies the SQLite-backed Durable Object migration, and creates the `CHAT_GATEWAY` binding defined in `wrangler.jsonc`. It keeps secrets stored on the existing Worker. No third-party runtime library is shipped with the backend or iOS app.

If Wrangler asks you to confirm differences between dashboard and local configuration, check that the Worker name is **xiaoliao-api**. The repository configuration supplies the model and binding. Do not delete the existing OpenAI secret. Do not paste only `worker.js` into the dashboard editor: this implementation also needs its binding and migration.

Check the deployment without calling OpenAI:

```sh
curl -i https://xiaoliao-api.leeharriswilliamson.workers.dev/health
```

Expect HTTP 200 and `{"service":"xiaoliao-api","status":"ok","version":1}`. This checks the deployed route, not OpenAI billing/model access or credentials. The first app conversation checks those. A bare visit to `/` intentionally returns 404.

The server model is configured by `OPENAI_MODEL` in `wrangler.jsonc`, initially `gpt-6.1-terra`. Changing provider/model later does not require putting provider credentials or provider-specific request formats into SwiftUI. Check your OpenAI project's billing/credit and model access if an authenticated conversation reports the provider unavailable. A ChatGPT subscription does not supply API billing.

## 3. Configure Xcode locally

1. Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables.
2. Add **`XIAOLIAO_API_TOKEN`** with the same beta token saved as Cloudflare's `XIAOLIAO_CLIENT_TOKEN`; enable its checkbox.
3. Use the **Debug** Run configuration and launch from Xcode. Do not put `OPENAI_API_KEY` here.

The Worker URL is already set in `ConversationReplyService.swift`; no URL setting is required. For another HTTPS development deployment, Debug accepts `XIAOLIAO_API_URL` as the base URL. Environment variables supplied by Xcode are for development runs, not a way to configure an independently installed release. Keep scheme settings under ignored `xcuserdata`, not a shared scheme checked into Git.

## 4. Mac acceptance

Build with the existing iOS 26.5+ SDK, then run `ConversationReplyTests` and the existing conversation/history/statistics unit suites. No iOS compilation or Swift test pass has been verified in this Linux workspace. The backend's native Node tests use mocked provider responses and an in-memory storage double; they are not a deployed Cloudflare integration test.

Manually verify:

1. Start a new topic. Expect the outlined “…” oval followed by one English partner message, with no seeded learner message. New live conversations start with the text composer. The prompt-suggestion button still uses its existing local example.
2. Send text, then edit the latest learner message after its reply arrives. Expect a fresh exact-version reply; retain the old message version, earlier replies, and separate practice counts. Original communication-method colors must remain stable.
3. Change tone, vocabulary, and reply length; the next partner turn should reflect them. Arm the existing blue system mode, ask for simpler words, and check that one Chinese system reply appears and the saved vocabulary setting changes. No extra partner turn should be added. Ask to change the topic/role and check that subsequent partner turns follow the recent system exchange.
4. Disable networking and send text. The learner message must remain saved, with Retry and “暂不重试”. Reconnect and retry: one reply appears. Sending/editing/recording is blocked while a response is pending; dismissing a failed wait keeps the learner message and permits further messages. There are no automatic paid retries.
5. Send, then switch to another conversation or start one. A late reply must update only its original history entry, preserving the active draft/settings. Change settings while a system request runs: controls changed since sending must not be rolled back by its result.
6. Interrupt/force-quit with a request pending. Reopen that history entry: offer an explicit retry using the saved ID/body. Completed requests are recoverable from the backend cache for 24 hours. A timeout/restart or an expired cache can cause another provider call; this is not an exactly-once billing guarantee. Stable local result IDs and atomic saves prevent duplicate reply bubbles.
7. Check small/large iPhones, Dynamic Type, keyboard avoidance, VoiceOver loading/retry labels, and existing local recording/playback behavior. Real recordings are still audio-only and do not request an AI reply. The isolated UI-test launch path remains offline and uses fixtures, never your API token or normal history.

## Contract and data handling

`POST /v1/conversations/respond` requires `Authorization: Bearer <beta token>`. Requests contain an immutable UUID, conversation ID, initial prompt, current settings, the latest versions of up to 40 recent text/transcribed turns, target exact-message ID, and `partner`/`system` kind. Context is limited to 24,000 UTF-16 characters; topic/individual turns to 4,000. Older context is omitted as complete turns, never silently truncating the new message. No audio files, local filenames, statistics, API credentials, or device identifiers are sent to OpenAI.

The app-level `systemAssistance` purpose remains user data; it is not exposed as a provider's privileged system role. Server-authored instructions define the two response modes. Strict structured output contains reply text and typed settings; normal partner replies cannot mutate settings. Blue replies may adjust supported settings, while recent blue exchanges also carry conversational topic/role guidance. There is no durable unlimited-context memory or profile tuning yet.

The Durable Object enforces beta-wide limits of 10 new provider attempts per minute and 200 per UTC day, including failed attempts. These protect the single shared beta credential, not individual user accounts, and are not a dollar-budget guarantee. Cached completions bypass the new-attempt limit. It retains request hashes and completed reply text/settings for retry recovery, expiring at 24 hours and removing them on the next hourly alarm. It does not store the input prompt/history or OpenAI key. HTTP responses disable caching; application observability is disabled; application code does not log credentials or conversation bodies.

OpenAI requests use `store: false`. This does not guarantee zero retention under the provider's abuse-monitoring policies. Before broader distribution, add account authentication, per-user quotas/ownership, deployment integration tests, and a reviewed privacy/retention policy. None of those are simulated in the app.

Official references: [OpenAI Responses text generation](https://developers.openai.com/api/docs/guides/text), [structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [GPT-6.1 Terra](https://developers.openai.com/api/docs/models/gpt-6.1-terra), [Cloudflare secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [Durable Objects](https://developers.cloudflare.com/durable-objects/get-started/), [Wrangler deploy](https://developers.cloudflare.com/workers/wrangler/commands/#deploy).
