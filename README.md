# XiaoLiao

小聊 is a native SwiftUI iOS app for Chinese speakers practicing conversational English.

**Current design authority:** [AGENTS.md — Design source and constraints](AGENTS.md#design-source-and-constraints). Concept 02 supersedes the original UI and Concept 01. Old Figma frames, bundled rings/tails and historical implementation notes must not be used to restore the former appearance. [Artwork documentation](Docs/FIGMA_ASSETS.md) separates current usage from legacy provenance.

The approved Concept 02 visual style is now applied in SwiftUI: deeper green/terracotta, warm white cards, softer outlines, regular text, rounded controls and a warm history drawer. Partner replies offer a voice card with an English transcript toggle; learner recordings keep their captions. Rhythm dots are static word-position marks for now—speech-aligned highlighting is not implemented. Rebuild on the Mac and check the updated screens against Figma; this Linux workspace cannot compile or render SwiftUI.

**Learning preferences:** in Conversation Settings, enter interests, learning goals or conversation style and tap **Save learning preferences**. Clear and save to remove them. They are saved locally and sent as guidance with new AI requests across all conversations; pending requests/retries retain their original snapshot. Lasting blue-message adjustments override the conversation prompt, which overrides overall preferences; explicit conversation controls still govern their own options. Lasting adjustments are saved per conversation and survive relaunch/long chats. Nothing in chat silently rewrites your overall preferences.

**This feature needs the updated Worker deployed:** run `npx wrangler deploy` from `Backend`, then rebuild the app. No new secrets are needed. Free-form preference interpretation still needs live acceptance; no inferred performance profile or research collection is implemented.

The prototype keeps conversations, settings, message edit versions, and recordings locally. The deployed Cloudflare Worker supplies OpenAI text replies: topics/settings shape the partner, and blue system requests can answer questions or adjust the conversation. Loading, failure, explicit retry, and saved pending requests are included. The user confirmed live chat works; [the setup guide](Docs/BACKEND_SETUP.md) records configuration.

The user confirmed live grammar statistics work for **new typed practice messages and every new text edit**, without backfilling old history. Evaluation runs independently of chat, saves applicable correct/incorrect/uncertain opportunities, and populates the existing overall grammar charts. Failed/interrupted analysis offers a separate retry in statistics and never counts as a grammar mistake. See [grammar setup and pending quality review](Docs/GRAMMAR_EVALUATION.md); model judgment accuracy still needs review.

On-device English recognition is now implemented for newly sent recordings and recorded replacements. It preserves the audio, attaches a transcript to the same spoken message, and connects that text to replies, grammar, and local statistics without double-counting the message. Build and test this client update on a supported physical iPhone; [speech setup and checks](Docs/SPEECH_RECOGNITION.md) cover model downloads, retry, relaunch, and limitations. No speech backend redeployment is needed.

**For grading:** open Menu → the gear → **Grading Mode / 评分模式**. Enabling it immediately changes app controls, instructions and statistics labels to English, and the preference survives relaunch. Turn it off to restore Chinese for those controls. Error messages always appear in English, including with Grading Mode off. Conversation content stays as-is; system permission prompts/keyboard follow device language. No Cloudflare redeployment is needed.

Navigation uses one rounded menu button with a terracotta glyph across conversation, settings and statistics screens. The warm Concept 02 drawer combines 开始新对话, 学习进度, Conversation Settings and saved history. The feed’s upper-right statistics button opens results for that conversation, with a Return to conversation button. History-row statistics controls remain unavailable. The overall dashboard retains its charts, table and calculations within the new warm card styling; its header opens the same menu.

Typed input now has a visible Send arrow inside the text box, including blue system-message mode and edits; Return remains supported where the keyboard provides it.

The recording row now keeps its waveform clearly visible during capture. Pause inside the green indicator ends capture; subsequent taps play/pause the take. The separate Restart button discards the unsent take and begins again from zero.

Partner text replies now support on-demand English playback using Apple’s built-in voice. Tap the voice card’s play control or select a reply and tap Play; tap again to pause/resume, or replay after it finishes. Use the English transcript toggle to reveal its text. Recording or leaving the feed stops playback. Blue system replies stay text-only. This client update needs no Cloudflare deployment or new key; the latest presentation and playback transitions still need device testing. See [speech checks](Docs/SPEECH_RECOGNITION.md#partner-reply-playback).

Graders can now enter a separate, revocable code under **Grading access** in Conversation Settings; it is verified and saved in the device Keychain. They need no OpenAI key, Cloudflare account, or Xcode token. **Owner setup requires adding `XIAOLIAO_GRADING_TOKEN` and deploying the updated Worker:** follow [the grader setup guide](Docs/GRADING_ACCESS.md). Grading Mode controls English labels independently.

The OpenAI key stays in Cloudflare. Private Debug runs can still use the developer beta token; Release builds accept a saved grading code and never embed credentials. Tests/previews retain isolated offline fixtures. Pronunciation scoring, cloud-generated partner voices, clause/vocabulary judgment, and production account authentication remain future work.

Committed learner text and text edits receive automatic local word/sentence analysis. Open the menu and choose 学习进度 for overall results, or tap the feed’s upper-right statistics button for the current conversation. Both show grammar results, sentence totals, newly observed vocabulary and vocabulary diversity (MATTR). Conversation reports count only that session’s attempts; vocabulary first-use still checks all local history. Opening either view waits for pending local extraction, never AI evaluation. Results refresh when local/grammar analysis finishes. Grammar stays unknown until its actual analysis succeeds; clause metrics remain unavailable.

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

Start with `GradingAccessTests`, `SpeechTranscriptionTests`, `GrammarEvaluationTests`, `ConversationReplyTests`, `TextAnalysisPipelineTests`, and the audio/history/statistics suites. All 40 backend tests passed here with mocked provider/storage; run them with `npm test` from `Backend`. Swift tests and actual speech/model checks still require Xcode and supported hardware. The optional `review:grammar` tool runs one public reference case against the deployed evaluator when explicitly given a local beta token; `--list` stays offline. The UI suite retains isolated offline flows. Build/test status and manual acceptance steps are tracked in [PLAN.md](PLAN.md); project conventions live in [AGENTS.md](AGENTS.md).
