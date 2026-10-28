# XiaoLiao (小聊)

Native SwiftUI iOS app for Chinese speakers practicing conversational English.

## Repository

- `XiaoLiao.xcodeproj`: existing Xcode project; app, XCTest, and UI-test targets.
- `XiaoLiao/XiaoLiaoApp.swift`: app entry point.
- `XiaoLiao/ContentView.swift`: root navigation and shared feature state supplied by the app entry point.
- `XiaoLiao/Features/Conversation/`: conversation models, local fixtures, view model, and views.
- `XiaoLiao/Features/Conversation/ConversationAudioController.swift`: local microphone, recording review, playback, and temporary audio-file lifecycle.
- `XiaoLiao/Features/Conversation/ConversationHistoryStore.swift`: local SwiftData history and durable recording-file storage.
- `XiaoLiao/Models/`: canonical messages/observations, MessageTextAnalysis, conversation/daily statistics snapshots, and vocabulary first-use records.
- `XiaoLiao/Features/Statistics/`: local extraction/calculation, overall-dashboard observable model, charts/table, and debug-only preview fixtures. No automatic evaluation pipeline or current-conversation statistics UI.
- `XiaoLiao/Features/Conversation/MessageAction.swift`: presentation actions for the canonical message model.
- `XiaoLiao/Design/`: shared colors, background, and artwork controls.
- `XiaoLiao/Assets.xcassets`: bundled Figma artwork and colors.
- `XiaoLiaoTests/`, `XiaoLiaoUITests/`: behavior and navigation tests.
- `PLAN.md`: milestones, validation status, and open design questions.

The project uses explicit Xcode groups and file references following a workaround for source folders missing from the Project navigator. When adding Swift files, add their file references to the appropriate group and register each once in its target's Sources build phase. Register asset catalogs once in Resources; keep project documentation out of build phases. Avoid other unnecessary project-file edits. Preserve the existing iOS 26.5 deployment target, bundle identifiers, signing, Swift language mode, and concurrency settings unless explicitly asked to change them.

## Architecture and conventions

- Use SwiftUI and lightweight MVVM. Keep navigation in the root, presentation in views, state transitions in the feature view model, and mock content in a separate fixture.
- Use value-type, identifiable messages and typed enums for actions and UI state. Use `@Observable` for the view model, `@State` for its owner, and `@Bindable` where views edit its properties. UI state belongs on the main actor.
- Store each message's sender, original communication method, and purpose explicitly. Practice speech uses green bubbles/white text; typed practice messages use white bubbles/black text. System requests use light blue/black and system replies use dark blue/white regardless of composer state. Retain this metadata in history.
- Only the learner's most recent message may offer Edit; a later partner reply does not remove that eligibility. Hide Edit on older/partner messages and enforce the same policy when beginning and committing edits. Text/fixture-transcript edits use the text composer; real recorded messages use the Figma recording row to record a replacement. Append a new immutable Message version on a successful edit; retain the original message and audio permanently while referenced by its edit history.
- Use feature directories; extract shared controls only when actually reused. Avoid speculative repositories, dependency containers, coordinators, and service protocols.
- Keep data local and deterministic initially. Milestones one and two use in-memory state: no backend, AI API, authentication, network service, API keys, analytics, or disk persistence. Do not imply that canned content is generated or translated live.
- Milestone three permits real local audio using Apple AVFoundation/AVFAudio. Request microphone permission only when the user starts recording. Unsent recordings use app-owned temporary files. Milestone four A now permits local persisted history: copy committed clips into Application Support before saving conversation metadata. Keep temporary cleanup separate from durable recordings. Speech recognition, synthesized partner speech, uploads, and backend integration remain unauthorized.
- Use the concrete main-actor `ConversationHistoryStore` and one SwiftData record per session, with a versioned Codable payload. Store only relative recording filenames in payloads so references survive sandbox relocation. Initialize the persistent view model once at app entry; plain view-model initializers and previews stay in memory. Pure persistence values and the SwiftData envelope type are explicitly `nonisolated` under the retained default-main-actor build setting; UI state stays on the main actor.
- Save starts, committed messages/edits, recordings, and current-session settings immediately. Commit visible changes only after disk save succeeds; keep unsent text/audio available on failure and roll settings back. Do not silently reset a damaged/unsupported store. Reclaim orphaned recording files only after a successful complete history load; all recordings referenced by any original/edit version remain retained. Replaced recordings are still referenced and must not be reclaimed. Missing clips must not erase text/settings or simulate playback.
- Audio UI state belongs to the main-actor observable audio controller, owned by the feature view model. Close recording segments before playback and join PCM buffers off the main actor. Invalidate pending permission/finalization work on cancellation or navigation, and recheck the active session and latest-message edit policy before committing. Stop recording/playback on backgrounding, audio interruptions, loss of the selected audio device, and media-service failures; never restart automatically.
- Add no third-party dependencies unless necessary. Prefer Apple frameworks. Bundled PDF artwork is a build asset, not a runtime rendering dependency.
- Use native layout, scrolling, text input, safe areas, and navigation. Preserve custom Figma artwork rather than replacing it with similar SF Symbols. Use SF Symbols only where the design names them.
- Centralize brand colors. Use semantic text styles or scaled metrics for custom display sizes; provide VoiceOver labels, selection state, and at least 44-point action targets. Respect Reduce Motion. Do not bake a whole screen screenshot into the UI.
- Add focused tests for consequential state transitions and navigation. Never claim tests passed or compilation succeeded unless the relevant command actually ran successfully.
- Keep changes scoped to the requested milestone/follow-up. The current authorized follow-up implements the overall statistics dashboard using the requested visualizations and existing brand styling. The user waived close Figma fidelity for this dashboard and restored tense consistency in the category list. Current-conversation statistics, grammar/clause evaluators, automatic analysis collection/lifecycle refresh, general settings, cloud sync, authentication, and AI/backend integration remain future work.

The canonical models in `Models` use immutable Codable/Equatable/Sendable value snapshots and explicit `nonisolated` types. Message includes identity, conversation, creation time, sender/purpose, original modality, content, reply linkage, revision, optional transcription/confidence, audio reference/duration, and status. GrammarObservation groups applicable rule opportunities with correct/incorrect/uncertain outcomes. VocabularyObservation groups word/phrase occurrences and their category assessments. Shared metadata records message revision/text source, evaluation time, evaluator/method/rubric/taxonomy versions, and optional confidence once per evaluation. Spans use explicit UTF-16 offsets/lengths. Category identifiers stay separate from localized labels. Pronunciation, topic relevance, grammar/clause evaluation, and current-conversation statistics are not implemented. The overall dashboard visualizes available analysis only. LocalTextAnalyzer supplies explicit word/sentence extraction; StatisticsCalculator derives rebuildable summaries from persisted analysis inputs. ConversationSession validates message/edit/reply identity and links, observation source eligibility and exact revision, UTF-16 source bounds, vocabulary surface text, unique IDs/categories, and finite confidence values in 0...1 before state/storage commits. Session arrays hold one active evaluation of each type per exact message version; recording a new result replaces only that version’s evaluation. No observation means not evaluated; an explicitly stored empty result means no applicable entries. Never fabricate evaluations on send/edit or carry an original’s results over to its replacement.

Message edits are separate immutable Message records: each has a unique `id`/`createdAt`, shares `logicalMessageID` with the original, and links to its immediate predecessor through `replacesMessageID`. Originals use their own ID as logicalMessageID, nil replacement link, and revision 1. Derive `isEdit` from the replacement link. Reply links and observation message IDs reference exact versions. ConversationSession.messages and ConversationViewModel.messageVersions retain all versions in append order. The feed uses the latest version per logicalMessageID in the original row position, with stable logical row identity; actions target the latest exact ID. Statistics count EVERY eligible original/edit version as a separate complete practice attempt, including unchanged text. Deduplicate exact record IDs, never logicalMessageID, for statistics. The feed still projects only latest versions. No revision-history UI is implemented.

Canonical history uses payload version 2 under `Application Support/XiaoLiao/ConversationData-v2/`, with `History.store` and `Recordings/*.caf`. Compatibility was waived for this prototype: the previous store is left untouched and is not loaded or migrated. Persist only opaque fixture keys or validated relative UUID recording filenames in Message; resolve local URLs through the store or the view model’s temporary-recording registry. LocalAudioClip describes audio operations, not persisted message data.

## Statistics contracts

- Count only complete learner conversation-practice records with explicit interaction origin. Exclude partner/system exchanges, fixture content, pending/failed/unknown-status records, and older records with unknown origin. New mock messages carry fixture origin; an actual learner edit of a fixture becomes an interaction. Unknown legacy origins remain excluded without guessing or resetting history.
- Session.textAnalyses stores at most one active structural analysis per exact message version. Validate source/revision, non-overlapping ordered UTF-16 spans, exact word surface text, normalization version, sentence membership, and optional nonnegative clause results with evaluator provenance. Re-evaluation replaces only that version’s analysis; originals/other edits retain theirs.
- Five tracked grammar category IDs are verb-tense, tense-consistency, article-usage, preposition-usage, and subject-verb-agreement. The latest dashboard request explicitly restores tense consistency, superseding its earlier deferral. Calculate correct / (correct + incorrect); exclude uncertain opportunities from the denominator. No scored opportunities means nil accuracy, not zero.
- Vocabulary uses word forms, never lemmas: run/runs/running differ. Normalize case and apostrophes under versioned English-oriented Latin-token rules; exclude punctuation/numerals/emoji/Chinese-only units. Local sentence counting uses Apple sentence segmentation for units containing accepted words; it is not a grammatical-completeness judgment. VocabularyObservation remains selective judgment data, never a full token inventory.
- MATTR uses the ordered analyzed word sequence, including repeated occurrences and all eligible edit versions. Window size is configurable (initial default 50); insufficient words produce nil, with no silent smaller-window fallback. Overall/day scores are recomputed from their words, never averaged from conversation scores. Scores based on partial text must be presented with analysis coverage.
- Unknown sentence/clause/word results remain nil. Clause ratios use total clauses / total sentences from the SAME clause-analyzed attempts. Report coverage separately from totals. Persist new analyses only after successful saves; failed writes preserve existing results.
- VocabularyHistoryEntry records earliest observed word-form use at the message submission time, with exact message/conversation IDs. Build first use across all supplied history BEFORE date filtering; older late transcripts can move first use earlier. These dates do not assert acquisition or mastery. For account-wide results supply all local sessions, not just the open conversation.
- Statistics snapshots include conversation, overall, and calendar-day results, calculation/normalization configuration, generation time, and reporting interval. Reporting intervals are half-open [start, end). Day boundaries use the caller’s calendar/time zone and message submission dates. Daily output is sparse; absent days are not fabricated evaluations.
- Analysis inputs are persisted; summaries and vocabulary inventory are derived Codable snapshots rebuilt on explicit request. No stale summary cache, automatic analysis, background lifecycle trigger, or extra SwiftData schema is added yet. ConversationViewModel.statisticsSnapshot captures history then calculates off the main actor using Sendable value snapshots. The existing header stats control now opens the overall dashboard on both conversation screens. No current-conversation dashboard/filter is implemented. Recalculate on opening the dashboard; capture stored history and compute off the main actor. Unreadable storage must throw rather than masquerade as an empty result.
- Keep payload version 2 and the existing directory. Missing new textAnalyses decode as an empty array, optional legacy origin decodes as unknown, and all existing history/audio remains readable. Never backfill invented evaluations.

## Overall statistics dashboard

- Root navigation owns the route and Back action. Both existing stats icons open the same overall, all-conversation view, independent of the active session. Preserve the previous route and New Conversation prompt when returning; existing leave-feed rules still stop playback and discard unsent recordings/system requests.
- Use paper texture/cream cards, brown outlines/text, green plots, Apple system fonts, and original Back artwork. The user explicitly permitted a new dashboard layout without close Figma matching. Keep a persistent Back header, native vertical scrolling, Dynamic Type, 44-point category targets, selected-state accessibility, and VoiceOver values. No extra date filter/tab/sheet or current-conversation view is added.
- Align all five categories on a horizontal 0–100% bar chart. Each full row is a button, including measured-zero or unscored rows. Highlight selection and show its daily accuracy line below. Percentages aggregate opportunity counts, not averages of daily rates. Unknown proficiency is a dash, never a fabricated zero.
- Use Apple Swift Charts for selected-category accuracy and MATTR lines and daily first-observed-vocabulary vertical bars. Time axes use calendar-day timestamps with year/month/day labels. Accuracy and MATTR domains remain 0...1; accuracy labels use percentages, MATTR labels use decimals. Point marks retain single-day observations. Split lines across missing/unscored days instead of joining gaps; keep measured zeroes.
- Activity is a two-column metric/value Grid: sentence total, clause total, clauses per sentence. Show unknown results as dashes, coverage counts for partial analyses, and the matched clause-denominator explanation. Do not invent assessments or count fixture content just to populate the dashboard.
- StatisticsDashboardModel owns loading/failure/selection and ignores stale async completions. Reopen requests a fresh snapshot; failures expose retry without deleting data. Normal app history is never seeded with sample statistics.
- StatisticsPreviewData is DEBUG-only, used by two named Xcode previews and an isolated UI-test switch. App seeding requires BOTH a valid UUID XIAOLIAO_UI_TEST_STORE and XIAOLIAO_UI_TEST_STATS_FIXTURE=1; it uses in-memory sample sessions and never the person's persistent directory. Release builds cannot enable this mode. These manual sample evaluations are not AI output.

## Design source and constraints

[Figma project_V2, mockup page](https://www.figma.com/design/jVSZ8R37YkVCJOC32lLmMR/project_V2?node-id=1-3)

Primary references:

| Frame | Node | Purpose |
| --- | --- | --- |
| New_conversation_init | `1:859` | Empty topic field, disabled chat button |
| new_convo_with_prompt | `1:887` | Filled topic field, enabled chat button |
| Conversation Feed | `7:36` | Default voice-mode feed |
| Conversation Feed | `1:980` | Selected partner audio and actions |
| Conversation Feed | `7:99` | Selected learner text and actions |
| typed_message | `1:1035` | Existing text input pattern |
| V2 • message_transcribe | `2:175` | Inline mock transcript |
| V2 • translate_own_message | `2:371` | Inline mock translation |
| new_convo_with_prompt (drawer open) | `1:914` | Conversation history drawer |
| V2 • conversation_settings | `2:56` | Tone, vocabulary, and reply-length controls |
| V2 • recording_audio | `2:121` | Inline recording row with Pause, waveform, Send |
| V2 • playback_own_message | `2:303` | Active Play action and inline playback timeline |
| V2 • edit_message | `2:432` | Record a replacement for the latest recorded message |
| V2 • message_loading | `2:505` | Future partner-response loading; do not fake a service request |
| V2 • message_sent_voice | `2:537` | Return to the idle feed after sending |
| user_message_to_system | `24:89` | Armed light-blue text composer, disabled microphone |
| user_message_to_system_sent | `24:189` | Light-blue user request on the right |
| system_response_to_user | `24:236` | Dark-blue text reply on the left with white border |

Preserve the cream paper texture, brown outlined controls, green text bubbles, red voice control, Chinese UI copy, English messages, spacing, and adjacent action rails. Device outline/corner mask and status/home indicators in the mockup are device chrome, not app artwork. Use real scroll indicators; do not draw a fake scrollbar for a short feed.

Do not invent screens, tab bars, menus, sheets, or interactions outside the requested scope. The overall dashboard is explicitly authorized with flexible layout and the existing brand vibe; follow its chart/table specifications below. For other missing design states, inspect Figma or request specific screenshots instead of guessing. The history control now opens the designed drawer on both conversation screens. The user explicitly approved a “新对话” row at its top and Apple system fonts in place of Inter for the new history/settings views. This replaces the milestone-one temporary history-to-New-Conversation mapping. Both gear controls open Conversation Settings; settings apply immediately to the current conversation or new-conversation draft, with no added Save action. Keep current-conversation statistics, general settings, and regeneration unavailable. The former bottom-left speaker control now toggles system-message mode as explicitly approved. Playback is available only for real local clips; the original fixtures have no audio files. Do not simulate successful recording, playback, transcription, or live AI responses.

Conversation adjustment now happens inline, replacing the old `2:89` textbox/modal design. The user confirmed that the bottom-left head/arrow control toggles/cancels the next message's system purpose, system requests are text only, and system replies are always text. Arm the blue composer and focus the keyboard; disable microphone/recording and edit entry while armed. A successful send disarms the mode and restores the previous voice/text composer. Blank/failed sends retain the mode/draft. Leaving the feed/history/settings clears an armed request and its unsent text. Persist request/reply purposes, not the armed UI state. Blue messages have no contextual rails in the supplied designs; older practice messages do not regain Edit after a newer learner system request.

Local system replies are visibly marked “本地示例”. Only the exact fixture “你能用更简单的词吗？” changes the saved vocabulary setting to Simple; “当前对话设置是什么？” reports actual local settings. Other requests receive an explicit placeholder. Persist request, reply, and any setting change together, without appending a partner response. Partner replies remain canned. This app-level system purpose is separate from any future AI provider's privileged system-instruction role. The user waived compatibility work for this prototype; do not add migration/reset flows or clear saved history without need.

For milestone three the user approved reusing the existing recording row: Pause finalizes audio for review, tapping its waveform previews/pauses it, tapping Pause again resumes recording, and keyboard switching or leaving the feed discards the unsent recording. Keep the red recording button dimmed/unavailable while this row is open. Use the original exported Pause, Send, and waveform artwork. Use native alerts for microphone denial/audio failures. Real recordings use the existing green learner bubble with “语音消息 · [duration]” and playback; transcription/translation stay unavailable until speech integration. Keep the existing text/fixture editing behavior. Show processing only during actual local file finalization; do not invent a partner-loading delay or a canned response after recording.

An initial prompt is required: users must type one or tap the prompt suggestion button (a deterministic local fixture for now). The user confirmed that the earlier “optional” wording was a mistake. Retain the coffee/turtle mock mistranslation for now, as explicitly requested.

History entries now retain their committed messages, original communication methods, settings, ordering, and recordings across launches on the same installation. Production history begins empty and contains only conversations the user starts; B–J/turtle history rows remain test/preview fixtures. New Conversation clears the draft, selection, and settings to the Figma defaults without altering saved entries. Reopening history clears transient selection/unsent edits and restores that entry. Launch on New Conversation and reopen saved entries through the existing drawer; do not persist navigation, selected actions, unsent topics/messages, or recording drafts. Local titles use the turtle fixture label or a short prompt prefix; do not generate titles or add new history controls/empty-state screens.

Unit persistence tests use temporary directories. Debug UI tests use a unique UUID in `XIAOLIAO_UI_TEST_STORE` to select an isolated Application Support store; relaunch tests reuse that UUID. Never clear or reuse the person's normal history store for automated tests. There are no iCloud entitlements or remote services in milestone four A.

Asset provenance is recorded in `Docs/FIGMA_ASSETS.md`. Never use temporary Figma URLs at runtime. Preserve original image proportions and asset-layer composition.

## Validation

On a Mac with an SDK/runtime supporting the existing deployment target:

```sh
xcodebuild -list -project XiaoLiao.xcodeproj
xcodebuild -project XiaoLiao.xcodeproj -scheme XiaoLiao -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -showdestinations -project XiaoLiao.xcodeproj -scheme XiaoLiao
# Replace the destination ID with an available iOS 26.5+ simulator.
xcodebuild -project XiaoLiao.xcodeproj -scheme XiaoLiao -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' test
```

Check the requested screens against their Figma frames on a large iPhone, then check a smaller iPhone, landscape, Dynamic Type, keyboard avoidance, and VoiceOver. Linux source/asset checks cannot substitute for an Xcode build or simulator comparison.
