# XiaoLiao

小聊 is a native SwiftUI iOS app for Chinese speakers practicing conversational English.

The prototype keeps conversations, settings, message edit versions, and recordings locally. The deployed Cloudflare Worker supplies OpenAI text replies: topics/settings shape the partner, and blue system requests can answer questions or adjust the conversation. Loading, failure, explicit retry, and saved pending requests are included. The user confirmed live chat works; [the setup guide](Docs/BACKEND_SETUP.md) records configuration.

The user confirmed live grammar statistics work for **new typed practice messages and every new text edit**, without backfilling old history. Evaluation runs independently of chat, saves applicable correct/incorrect/uncertain opportunities, and populates the existing overall grammar charts. Failed/interrupted analysis offers a separate retry in statistics and never counts as a grammar mistake. See [grammar setup and pending quality review](Docs/GRAMMAR_EVALUATION.md); model judgment accuracy still needs review.

On-device English recognition is now implemented for newly sent recordings and recorded replacements. It preserves the audio, attaches a transcript to the same spoken message, and connects that text to replies, grammar, and local statistics without double-counting the message. Build and test this client update on a supported physical iPhone; [speech setup and checks](Docs/SPEECH_RECOGNITION.md) cover model downloads, retry, relaunch, and limitations. No speech backend redeployment is needed.

Navigation now uses one red menu button across conversation, settings and statistics screens. The Figma navy drawer combines 开始新对话, 学习进度, Conversation Settings and saved history. Per-conversation statistics controls remain unavailable. The overall dashboard content is unchanged; its header opens the same menu.

Typed input now has a visible Send arrow inside the text box, including blue system-message mode and edits; Return remains supported where the keyboard provides it.

The recording row now keeps its waveform clearly visible during capture. Pause inside the green indicator ends capture; subsequent taps play/pause the take. The separate Restart button discards the unsent take and begins again from zero.

Partner text replies now support on-demand English playback using Apple’s built-in voice. Select a reply and tap Play; tap again to pause/resume, or replay after it finishes. Recording or leaving the feed stops playback. Blue system replies stay text-only. This client update needs no Cloudflare deployment or new key; actual voice playback still needs device testing. See [speech checks](Docs/SPEECH_RECOGNITION.md#partner-reply-playback).

The OpenAI key stays in Cloudflare. Private Debug runs use a separate beta token; Release builds do not embed shared credentials. Tests/previews retain isolated offline fixtures. Pronunciation scoring, cloud-generated partner voices, clause/vocabulary judgment, and production account authentication remain future work.

Committed learner text and text edits receive automatic local word/sentence analysis. Open the menu and choose 学习进度 to see overall grammar results, sentence totals, newly observed vocabulary, and vocabulary diversity (MATTR). Grammar stays unknown until its actual analysis succeeds; clause metrics remain unavailable.

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

Start with `SpeechTranscriptionTests`, `GrammarEvaluationTests`, `ConversationReplyTests`, `TextAnalysisPipelineTests`, and the audio/history/statistics suites. All 32 backend tests passed here with mocked provider/storage; run them with `npm test` from `Backend`. Swift tests and actual speech/model checks still require Xcode and supported hardware. The optional `review:grammar` tool runs one public reference case against the deployed evaluator when explicitly given a local beta token; `--list` stays offline. The UI suite retains isolated offline flows. Build/test status and manual acceptance steps are tracked in [PLAN.md](PLAN.md); project conventions live in [AGENTS.md](AGENTS.md).
