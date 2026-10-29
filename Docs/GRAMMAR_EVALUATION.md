# Grammar evaluation v1

Authorized scope: automatically evaluate **newly submitted text-backed practice messages and each new edit**, without backfilling existing history. The existing overall grammar charts consume the saved observations. This increment does not add inline correction screens, speech recognition, vocabulary judgment, clause counting, or current-conversation statistics.

## Deploy and try it

The chat Worker is already live. Deploy the updated backend from your Mac's `Backend` directory:

```sh
npm test
npx wrangler deploy
```

No new secret, storage binding, migration, model account, or Xcode environment variable is required. Reuse the working `OPENAI_API_KEY`, Cloudflare `XIAOLIAO_CLIENT_TOKEN`, and local Xcode `XIAOLIAO_API_TOKEN`. The first key name must include **OPENAI**, not `OPEN_API_KEY`. Build and run the updated Swift app after deploying the Worker. Existing saved messages stay unevaluated; send a NEW message or commit a NEW edit to queue grammar work.

If grammar statistics do not change, check the backend route separately from the app version. A live unauthenticated probe after the user's report returned HTTP 404 with `not_found`; the deployed Worker did not expose the grammar route even though the app was updated. Run `npx wrangler deploy` from the **Backend folder in the same updated checkout**. Then use **重试语法分析** in statistics to retry the saved failed jobs.

This diagnostic request contains no credentials or learner text and cannot call OpenAI:

```sh
curl -sS -i -X POST https://xiaoliao-api.leeharriswilliamson.workers.dev/v1/grammar/evaluate -H 'Content-Type: application/json' --data '{}'
```

Expect **401 unauthorized** when the route is deployed and its required configuration is present: this probe deliberately sends no beta token. **404 not_found** means the grammar route is missing from that deployment; **503 not_configured** means required Worker configuration is absent. A successful `/health` response alone does not verify the grammar route, credentials, or model evaluation. After deployment, failed analysis still requires the dashboard's explicit retry; relaunching alone does not resend it.

Suggested manual flow:

1. Send `She go to school every day.` and wait for the partner reply. Grammar runs separately; opening overall statistics must not wait for its network request. Its card shows pending/unfinished counts and refreshes as results arrive.
2. Expect an incorrect subject–verb agreement opportunity, with a correction to `goes`. Edit the message to `She goes to school every day.` and check that both versions retain separate observations and contribute to practice counts. Other applicable categories may also be evaluated; do not assume every bar must have a score.
3. Check `Yesterday I walk to the park.`, `I saw cat near the door.`, and `She depends of her parents.` for tense/article/preposition findings. Check `Yesterday I went to the shop and I buy tea.` for the unjustified tense shift.
4. Check legitimate changes (`Yesterday I walked home. Today I am resting.`), conversational fragments (`Coffee, please.`), contractions, and ambiguous references. They must not all be converted to errors. Missing/non-applicable/uncertain scores remain dashes, not zero accuracy or 100%.
5. Send/edit while another grammar request runs, switch conversations, leave an unsent draft, and change settings. Late results must update only their own exact message version, without overwriting newer state or locking the composer.
6. Interrupt networking during analysis. The chat message and partner reply remain intact; analysis failure never becomes a grammar mistake. The grammar card shows its reason and **重试语法分析**. Failed/interrupted requests require this explicit retry, preserving the original ID/body. Already attempted work is not silently retried on launch or stats opening.
7. Force-quit/relaunch. Queued but never attempted jobs resume; attempted/interrupted jobs offer retry. Saved observations survive and are not re-evaluated. Older unqueued history stays untouched, including when reopening statistics. Fixtures, partner/system messages, and real audio-only recordings do not queue work.

Private-beta limits: chat and grammar share 10 new provider attempts/minute and 200/UTC-day. Grammar additionally caps at **4/minute and 100/UTC-day** to leave chat capacity. One new typed practice message normally adds a second provider call for grammar. Failed provider attempts count toward quotas; cached recoveries do not. Wait for the quota window before manually retrying a batch. The app never automatically polls failed work.

## What the rubric counts

The versioned server rubric checks all five dashboard categories against the exact message text, without additional conversation context:

| Category | Opportunity rule |
| --- | --- |
| Verb tense | One finite verb group, with auxiliaries grouped; no separate scores for every word/auxiliary. Do not label a pure third-person `-s` error as a tense error too. |
| Tense consistency | A comparable adjacent finite-clause pair within the message, anchored on the later verb. Exclude different explicit timeframes and legitimate hypothetical/reported-speech shifts; use uncertain where context is missing. A single finite clause has no pair. |
| Articles | An applicable a/an/the/zero-article choice for a noun phrase. Count zero article where meaningful; avoid automatic successes for pronouns/proper names or phrases whose other determiner excludes article choice. Missing articles anchor to an existing noun phrase. |
| Prepositions | An actual or clearly required prepositional relation, including omissions; exclude adverbs/phrasal-verb particles. |
| Subject–verb agreement | A finite verb group with a real person/number contrast, including be/do/have. Exclude invariant modals, invariant lexical past forms, and nonfinite verbs. |

Applicable successes and mistakes are both stored. Uncertain outcomes are retained but excluded from correct/(correct+incorrect). No opportunity means not applicable, not a synthetic success. A complete empty evaluation is stored distinctly from a failed/missing evaluation. The percentage is accuracy on the evaluator's identified opportunities; it is not a standardized or calibrated proficiency score.

Suggestions and short Chinese explanations are stored on incorrect opportunities. Correct/uncertain opportunities have no suggested correction. Confidence is deliberately nil: no uncalibrated probability is invented. These explanations are data for later feedback UI; this increment only changes the existing statistics card and plots.

## Contracts and safeguards

`POST /v1/grammar/evaluate` uses the same beta authorization as chat, with a separate cache namespace. The request includes a UUID, exact conversation/message IDs, revision, text source, source text, and `grammar-v1`. Only new explicitly queued work is processed. Each source is limited to 4,000 UTF-16 units, and output to 128 applicable opportunities. The evaluator must report completion of all five categories; incomplete/truncated/refused output is rejected as a whole, rather than saving a misleading partial denominator. Longer/dense text may remain unevaluated if it cannot fit the bounded output.

The server uses Responses strict structured output, `store: false`, the existing server-selected `OPENAI_MODEL`, a bounded output budget, and the shared upstream timeout. Learner text is untrusted data, never developer/system instructions. The model quotes exact evidence and a repeated-occurrence index; the server computes UTF-16 offsets from that evidence, rejects nonexistent/duplicate constructions, and assigns stable opportunity IDs in the cached result. Swift validates identity/revision/source, taxonomy/rubric, exact source spans, outcomes/corrections, unique IDs, and finite metadata again before saving.

Pending jobs are persisted with their messages, before any paid analysis call. Marking a job attempted must save successfully before calling the backend. Results remove that job and append its observation in one validated save. A late result merges into CURRENT committed history; it never rewrites immutable message versions, navigation, drafts, settings, richer manual results, text analyses, or chat errors. Save failures keep missing work visible and preserve existing data. Keep the existing version-2 store; absent `grammarEvaluationJobs` decodes as an empty array, which is how old history avoids backfill.

Completed backend results expire after 24 hours and are removed by the existing hourly alarm. The grammar result contains quoted evidence/corrections, but the cache does not retain the full input text/history. Interrupted provider calls or cache expiry can result in another paid attempt; stable request/observation IDs and validated local upserts prevent duplicate statistics, not duplicate billing guarantees.

## Quality review

The backend tests use mocked Responses output. They prove contract validation, offset conversion, quotas, cache recovery, and error handling; they do **not** prove that the live model identifies all opportunities or judges grammar correctly. Swift tests inject controlled evaluators and likewise are not model-quality benchmarks. Results are provisional until reviewed against actual provider output.

`Backend/evaluation/grammar-cases.json` contains ten candidate reference cases across the categories, legitimate shifts/fragments, Unicode, and instruction-like learner text. Required/forbidden findings are a targeted subset, not exhaustive expert annotations or a calibrated benchmark. Inspect every returned opportunity and review the references before treating these metrics as reliable learning assessments.

List the cases without any network request:

```sh
npm run review:grammar -- --list
```

To explicitly run ONE case against the deployed Worker, set the beta token locally in Terminal. For a Mac Terminal using bash or zsh:

```sh
read -s XIAOLIAO_EVAL_TOKEN
```

Paste the beta token at that hidden-input prompt and press Return, then run:

```sh
export XIAOLIAO_EVAL_TOKEN
npm run review:grammar -- agreement-error
unset XIAOLIAO_EVAL_TOKEN
```

Each run requests one real evaluation and can incur one provider charge. Select another case ID to review it; respect the four-per-minute grammar cap. Never use the OpenAI key here or put tokens in command arguments/shared files/chat. The tool prints a reference comparison plus the full findings for that public example. A failed comparison needs human review; matching a few cases does not establish overall accuracy. `XIAOLIAO_EVAL_URL` optionally selects a different HTTPS Worker base URL.

## Validation status

Executed here: native Node backend tests and source syntax checks, plus the review tool's offline `--list` path. No real grammar provider calls or live grammar deployment were made. This Linux environment cannot build SwiftUI/SwiftData or execute XCTest; build and run `GrammarEvaluationTests`, `ConversationReplyTests`, the existing persistence/statistics suites, and manual device checks on the Mac. The user previously confirmed live chat works; that does not validate this new grammar route.

API references: [structured output schemas](https://developers.openai.com/api/docs/guides/structured-outputs), [evaluation practices and human review](https://developers.openai.com/api/docs/guides/evaluation-best-practices).
