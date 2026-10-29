# XiaoLiao

小聊 is a native SwiftUI iOS app for Chinese speakers practicing conversational English.

The prototype keeps conversations, settings, message edit versions, and recordings locally. A prepared Cloudflare Worker now supplies real OpenAI text replies: topics/settings shape the partner, and blue system requests can answer questions or adjust the conversation. Loading, failure, explicit retry, and saved pending requests are included. Deployment and Xcode configuration are required before live use; follow [the setup guide](Docs/BACKEND_SETUP.md). Nothing has been deployed from this workspace.

The OpenAI key stays in Cloudflare. Private Debug runs use a separate beta token; Release builds do not embed shared credentials. Tests/previews retain isolated offline fixtures. Speech recognition, partner audio, grammar/clause evaluation, and production account authentication remain future work.

Committed learner text and text edits now receive automatic local word/sentence analysis. Open the stats icon on either conversation screen to see overall sentence totals, newly observed vocabulary, and vocabulary diversity (MATTR). Grammar and clause metrics remain unavailable until their evaluators are added.

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

Start with `ConversationReplyTests`, `TextAnalysisPipelineTests`, and the statistics/conversation unit suites. Backend tests run with `npm test` from `Backend` and use mocked provider responses without credentials or paid calls. The UI suite retains isolated offline flows. Build/test status and manual acceptance steps are tracked in [PLAN.md](PLAN.md); project conventions live in [AGENTS.md](AGENTS.md).
