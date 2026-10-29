# XiaoLiao

小聊 is a native SwiftUI iOS app for Chinese speakers practicing conversational English.

The prototype keeps conversations, settings, message edit versions, and recordings locally. The deployed Cloudflare Worker supplies OpenAI text replies: topics/settings shape the partner, and blue system requests can answer questions or adjust the conversation. Loading, failure, explicit retry, and saved pending requests are included. The user confirmed live chat works; [the setup guide](Docs/BACKEND_SETUP.md) records configuration.

Grammar evaluation is now prepared for **new typed practice messages and every new text edit**, without backfilling old history. It runs independently of chat, saves applicable correct/incorrect/uncertain opportunities, and populates the existing overall grammar charts. Failed/interrupted analysis offers a separate retry in statistics and never counts as a grammar mistake. Redeploy the updated Worker and build the updated app before trying it; see [grammar deployment and quality review](Docs/GRAMMAR_EVALUATION.md). Live grammar judgments have not yet been validated.

The OpenAI key stays in Cloudflare. Private Debug runs use a separate beta token; Release builds do not embed shared credentials. Tests/previews retain isolated offline fixtures. Speech recognition, partner audio, clause/vocabulary judgment, and production account authentication remain future work.

Committed learner text and text edits receive automatic local word/sentence analysis. Open the stats icon on either conversation screen to see overall grammar results, sentence totals, newly observed vocabulary, and vocabulary diversity (MATTR). Grammar stays unknown until its actual analysis succeeds; clause metrics remain unavailable.

- Every submitted original and edit counts as a complete practice attempt.
- Word forms such as `run`, `runs`, and `running` count separately; capitalization is normalized.
- MATTR needs at least 50 analyzed words for its current window. Daily points need enough words on that day. A dash or missing point means unavailable, not zero.
- Fixture/system/partner content, unfinished sends, untranscribed audio, and older messages with unknown provenance are excluded from automatic text collection.
- Extraction/save failures retain the submitted message. Missing analysis retries on launch, foregrounding, and opening statistics; no network service is involved.

On a Mac with an SDK supporting the retained iOS 26.5 deployment target:

```sh
xcodebuild -project XiaoLiao.xcodeproj -scheme XiaoLiao -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
# Use an available simulator ID for the test destination.
xcodebuild -project XiaoLiao.xcodeproj -scheme XiaoLiao -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' test
```

Start with `GrammarEvaluationTests`, `ConversationReplyTests`, `TextAnalysisPipelineTests`, and the statistics/conversation unit suites. All 32 backend tests passed here with mocked provider/storage; run them with `npm test` from `Backend`. Swift tests still require Xcode. The optional `review:grammar` tool runs one public reference case against the deployed evaluator when explicitly given a local beta token; `--list` stays offline. The UI suite retains isolated offline flows. Build/test status and manual acceptance steps are tracked in [PLAN.md](PLAN.md); project conventions live in [AGENTS.md](AGENTS.md).
