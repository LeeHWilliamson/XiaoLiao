# XiaoLiao implementation plan

Current implementation: local conversations/history/audio, immutable message versions, the overall dashboard, and automatic local word/sentence analysis for committed learner text and edits. Grammar/clause evaluation, speech recognition, AI conversations, and current-conversation statistics are still future work. Mac build/runtime acceptance remains pending where noted.

The sections below record each milestone's scope and validation at the time. Later follow-ups supersede earlier deferrals; see AGENTS.md for current conventions and README.md for current usage.

## Initial inspection — 2026-10-26

The repository began as an unchanged Xcode SwiftUI starter: `XiaoLiaoApp` launches a `ContentView` containing a globe and “Hello, world!”. It has an empty AccentColor, an empty AppIcon, and template XCTest/UI-test targets. There were no existing feature models, design tokens, package dependencies, backend code, or project instruction files. The starter used filesystem-synchronized target folders, Swift language mode 5, main-actor default isolation for the app, and iOS 26.5 deployment settings. A navigator workaround now uses explicit file references; retain the original build settings.

Figma is accessible. The supplied link targets the `mockup` canvas; individual frames provide the usable design context. See `AGENTS.md` for frame links and conventions.

## Milestone 1 — local conversation UI

Scope: New Conversation, a basic Conversation Feed, navigation, Figma mock messages, and selection-driven contextual actions. Stop here after implementation and handoff.

- [x] Inspect the starter and the relevant Figma frames.
- [x] Record architecture, conventions, references, and constraints in `AGENTS.md`.
- [x] Bundle original Figma artwork and centralize design colors.
- [x] Add deterministic message fixtures and a small observable conversation view model.
- [x] Implement the empty/filled topic input, local prompt suggestion, and chat button.
- [x] Navigate into the feed and return using the existing history control (explicit user preference).
- [x] Show the five-second partner audio bubble and “Yes, I also love turtles!” learner bubble.
- [x] Show only the selected message's adjacent actions; tapping it again or the background dismisses them (source implementation; runtime check pending).
- [x] Support local transcript/translation toggles and the existing text input/edit pattern. Keep audio-related actions unavailable; add no live AI behavior.
- [x] Add focused behavior/navigation tests and perform the checks available in this environment.
- [ ] Build and run tests in Xcode; compare simulator rendering with Figma.

Acceptance: the target should remain buildable; users can enter or seed a topic, open the mock feed, select either message, reveal the appropriate action rail, and return to the topic screen. Any source-only checks must be reported separately from a successful build.

### Implementation and verification status

Milestone-one source work is complete. The user reported that the demo looks great; agent-side Xcode build/test acceptance remains unverified. The next authorized work is milestone two below.

- Added SwiftUI New Conversation and Conversation Feed views, shared artwork controls, typed message/action models, deterministic fixtures, and an observable main-actor view model. The root owns navigation and feature state.
- Added 27 original Figma image layers (PNG and vector PDF) and six color assets including AccentColor. Provenance and placement are documented in `Docs/FIGMA_ASSETS.md`.
- Added seven focused XCTest cases covering prompt validation, selection, details, editing, session reset, local submission, and asset loading, plus two UI flow tests. These tests have **not** run here.
- `git diff --check` passed. Static checks passed for all catalog JSON, non-empty image files, PNG decoding/CRC, PDF page proportions, named color references, and image callsites. A contact sheet of all imported artwork was inspected. No runtime network URLs or third-party package references were added.
- Follow-up navigator work adds root Markdown documents and the `Docs` group, and replaces synchronized app/test folders with explicit nested groups and file references. All Swift sources are registered once in their own target's Sources phase, and Assets.xcassets is registered once in the app Resources phase. Documentation stays outside build phases. The original iOS 26.5 deployment, bundle identifiers, signing, Swift language mode, and concurrency settings are retained. This is a workaround for folders present in Finder but missing from Xcode; navigator visibility on the Mac still needs confirmation.
- `xcodebuild -version` failed with `command not found` on this Linux host; no Swift toolchain is present either. No compilation, XCTest execution, simulator run, or comparison of the rendered app to Figma has occurred. Those remain required before declaring this milestone verified.
- Settings, stats/history drawer, speaker switching, recording, playback, and regeneration remain unavailable. Translation/transcription are fixture toggles; text edits/submissions only change in-memory data. Nothing survives relaunch.

### Xcode validation checklist

- Build with an iOS SDK supporting the retained 26.5 deployment target; run unit and UI tests.
- At 440-point reference width, compare colors, paper texture, artwork proportions, bubble placement, and action rails with `1:859`, `1:887`, `7:36`, `1:980`, and `7:99`.
- Verify blank/whitespace topics cannot start a chat, suggestion fills the exact Figma prompt, and the keyboard dismisses on navigation.
- Tap audio, learner text, the selected bubble again, and empty feed space. Only one rail should appear at a time, without shifting bubble alignment.
- Toggle the local transcript and translation, edit learner text through the composer, submit with the keyboard, and confirm there is no generated partner response.
- Toggle keyboard/microphone modes; check the composer stays above the keyboard and the feed can scroll with longer content.
- Return via history; confirm the topic is retained and starting again resets the mock feed and selection.
- Check smaller iPhones, landscape, iPad layout, large accessibility text, Reduce Motion, and VoiceOver labels/order. Real scroll indicators appear only when there is scrollable content.
- Confirm no microphone permission prompt or network requests occur. Settings, stats, recording, playback, and regeneration are intentionally unavailable.

### Product decisions confirmed 2026-10-27

1. An initial prompt is required. Users must supply one or click prompt generation; the current suggestion button supplies a deterministic mock prompt. The original optional wording was a design-copy mistake, and the placeholder now reflects the required input.
2. Leave the coffee/turtle mock mistranslation unchanged for now, as requested.
3. Replace the temporary history-to-New-Conversation mapping with the history drawer. The user approved a “新对话” row at the top because the Figma drawer has no create control.
4. Use Apple system fonts rather than Inter in the new history/settings views, as approved, with scaled text sizes.
5. Preserve the voice/text bubble palette. The user clarified that appearance follows the communication method used to send each message, rather than the current composer mode. Retain the reply-length labels from Figma, including “复杂”; no copy rewrite is part of this milestone.

## Milestone 2 — conversation history and conversation settings

Authorized scope: the history drawer (`1:914`) and conversation settings (`2:56`), using local state and the existing visual design. General settings and conversation adjustment remain future work. Stop after these two flows are ready for testing.

- [x] Inspect high-fidelity Figma context and screenshots for both flows.
- [x] Record the required-prompt decision, retained mock translation, approved New Conversation row, and system-font choice.
- [x] Add typed settings and session models with per-conversation in-memory messages/settings.
- [x] Open history from both screens, select/reopen an entry, dismiss with the red back control or scrim, and start a blank conversation via “新对话”.
- [x] Preserve the navy drawer, pale selected row, blue selection text, red back artwork, cream paper background, and tan/green settings capsules.
- [x] Enable tone, vocabulary, and reply-length selections; apply changes immediately and restore them with their history entry.
- [x] Register new source/test files in the explicit Xcode groups and build phases.
- [x] Add focused session-isolation tests and update UI flow tests for the new navigation.
- [x] Finish static project/asset checks and document validation limits.
- [ ] Build, run XCTest/UI tests, and compare both new views with Figma in Xcode.

History is intentionally in memory for this milestone and resets on app relaunch. It starts with the Figma “乌龟” and B–J fixture rows; those rows reuse the existing turtle mock messages. Newly started conversations appear first with their own identity. Committed edits/submitted messages and settings are retained while switching entries; unsent drafts and message-action selection are cleared. Settings chosen before starting a conversation apply to that new conversation. “新对话” resets settings to casual/medium/medium.

Both gear controls open Conversation Settings directly in this milestone. No general-settings intermediary or conversation-adjustment screen is implemented. Settings do not change the canned AI reply: no backend service is connected.

### Milestone-two validation status

- Static project checks passed: 15 app Swift files, three unit-test source files, and three UI-test source files are each registered once in the correct target. The asset catalog remains registered once in app Resources. Existing build configurations, target identifiers, signing, deployment target, and concurrency settings are unchanged.
- Static asset checks passed for all 30 image assets and 12 color assets: catalog JSON, non-empty PNG/PDF files, PNG integrity, PDF page proportions, Swift callsites, and named-color references. The new SVG artwork was downloaded from Figma and converted to vector PDF; the drawer/settings back art was verified identical before reuse. No runtime network client, temporary Figma URL, or third-party package reference was added.
- Added five session/history unit tests; added two UI flow tests and updated the earlier navigation test for the new drawer. These tests have not run here.
- The simulator build command failed with `xcodebuild: command not found` (exit 127). No compilation or simulator comparison is claimed. The following Xcode checklist remains the acceptance step.
- User-reported Mac test attempts: `XiaoLiaoUITests-Runner` on the iPhone 17 Pro simulator failed to initialize for UI testing with `Timed out waiting for AX loaded notification`, including a retry with parallel execution disabled. This is a runner initialization timeout, with no individual failed assertion supplied. UI-test acceptance remains pending. Collect exact Xcode/runtime versions and Activity Monitor readings if continuing diagnosis; neither limited RAM nor app code has been established as the cause. Do not change app assertions or mark tests passed based on this report. The user accepted proceeding with manual checks and has now authorized milestone three.

Milestone-two source implementation is ready for testing. The user reported that the flows look good and subsequently authorized milestone three. General settings, statistics, persisted history, and backend integration remain future work.

### Milestone-two Xcode checks

- Confirm Features, Design, the two new views, and the new history unit-test file appear in the navigator. Build with the retained iOS 26.5 deployment settings and run all tests.
- From New Conversation, check required prompt copy and generation; open/close history without losing the typed prompt. Open conversation settings, change all three controls, return, and start a conversation.
- From the feed, open history and verify the current entry is highlighted. Switch to B, change its settings, then reopen the earlier entry and confirm its messages/settings remain independent.
- Edit/send a local learner message, switch away and back, and confirm the committed content is retained. Start “新对话” and confirm the prompt is empty, Chat is disabled, settings are defaults, and previous entries remain available.
- Dismiss history using both the red arrow and outside scrim; check neither action activates controls beneath the drawer.
- Compare the drawer with `1:914` and settings with `2:56`, allowing only the approved New Conversation row/system-font substitutions and real safe-area layout.
- Verify history scrolling, small iPhones, landscape, iPad, large accessibility text, VoiceOver focus/selected values, and Reduce Motion. Verify settings Back returns to the correct originating screen.
- Relaunch and confirm the documented mock reset; persistence belongs to a future milestone. Recording, stats, and live AI generation must remain unavailable.

### Follow-up fixes — message appearance and editing

The user reported two issues: changing composer mode recolored earlier messages, and older learner messages could still be edited.

- [x] Store immutable sender/send-method metadata on messages. Mark the existing green learner fixture as a spoken response displayed as text; mark keyboard submissions as typed.
- [x] Use the message's send method for bubble/text colors. Preserve that method when editing or reopening history.
- [x] Show Edit only for the most recent learner message. Enforce eligibility in the view model both when an edit starts and when it commits; partner replies do not change which learner message is latest.
- [x] Add regression coverage for mixed communication methods, history restoration, editing the latest message, rejecting older/partner edits, and preserving the method when editing a spoken response.
- [ ] Build and run the tests in Xcode; check colors and contextual actions in the simulator.

Xcode checks: switch to keyboard input and back before sending anything; the existing green response must stay green. Send a typed message and switch to voice; the new message must remain white while the original remains green. Select both learner messages: Edit must appear only beside the latest one. Edit it and reopen the conversation through history; colors and edit eligibility must remain correct. Recording remains unavailable.

Validation: source review and `git diff --check` completed; the Xcode project file is unchanged because the changes and regression tests use existing registered files. The build attempt failed with `xcodebuild: command not found` (exit 127). The new tests and simulator checks have not run here.

## Milestone 3 — local audio practice

Authorized 2026-10-28. Implement real local recording/review/playback with Apple audio APIs, preserving the existing Figma feed. Stop after the flow is ready for Xcode/device testing. No live AI or speech recognition is included.

### Confirmed design and scope

- Inspected high-fidelity context and screenshots for recording (`2:121`), playback (`2:303`), voice editing (`2:432`), loading (`2:505`), and sent voice (`2:537`).
- The user approved reusing the designed Pause/waveform/Send row for review: Pause finalizes the current audio, tapping the waveform previews/pauses it, tapping Pause again resumes, and switching to the keyboard or leaving the feed discards the unsent recording. No new screen or review sheet is added.
- The user approved audio-only recordings displayed in the existing green learner bubble as “语音消息 · [duration]”. No invented English transcript, translation, synthesized fixture audio, or partner response is produced. Existing fixture details remain as before; their playback stays unavailable because they have no audio file.
- Only the latest learner message offers Edit. Real recorded messages record a replacement through the designed row; cancellation/failure preserves the original. Existing text and fixture-transcript edits keep using the text composer.
- The partner-loading bubble in `2:505` is reserved for actual service integration. Local processing is shown in the recording row only while permission/file finalization is genuinely pending. No artificial response-loading delay is introduced.

### Implementation

- [x] Add an observable main-actor audio controller using `AVAudioRecorder`, `AVAudioPlayer`, `AVAudioApplication` microphone permission, and `AVAudioSession` lifecycle handling.
- [x] Record mono PCM into app-owned temporary CAF files. Pausing closes the current segment; resuming starts another. Join segments in order using fixed-size buffers off the main actor so preview/send reads a finalized file without loading the entire clip into memory.
- [x] Add real recording duration and level feedback, inline review, pause/resume playback, Send, keyboard/navigation cancellation, and latest-recording replacement.
- [x] Retain committed clips through in-memory history switches. Delete cancelled segments, superseded reviews, and replaced clips; clear previous-run scratch files on the next controller initialization. History and clips are not restored on relaunch.
- [x] Handle denied microphone permission with a native alert and system-settings link. Handle recording, finalization, and playback failures without committing a fabricated message.
- [x] Cancel pending permission/finalization work on navigation/backgrounding/interruption. Stop playback on backgrounding, selected-device removal, and audio-service loss/reset. Never resume automatically.
- [x] Import the four original Figma Pause/Send/waveform layers, preserving their proportions, and reuse the existing paper, rings, message bubble, and inline timeline assets.
- [x] Register the audio controller and test source in explicit Xcode groups/Sources phases. Add `NSMicrophoneUsageDescription` to app Debug and Release only; preserve the existing build/signing/deployment/concurrency settings.
- [x] Add nine focused audio tests covering denied/cancelled permission, interruption while permission is pending, segment order/sample preservation, invalid audio, history retention and message colors, stale-session rejection, atomic replacement/cancellation, and latest-message editing. Extend the existing UI smoke flow to check that recording is enabled and recording-row actions are initially absent. No real microphone or playback is invoked by these automated tests.
- [ ] Build, run tests, and compare rendering in Xcode; verify the real recording/playback lifecycle on an iPhone.

### Validation status

The build command was attempted here and failed with `xcodebuild: command not found` (exit 127). No successful compilation, XCTest run, simulator rendering, or device audio test is claimed. The existing Mac UI-test runner initialization timeout remains unresolved; it is separate from a failed app assertion. Source/project/asset checks and the manual device checklist below are the handoff, not a replacement for runtime validation.

Static checks passed: the Xcode project parses, all 16 app/four unit-test/three UI-test Swift sources are registered once in their own targets, the asset catalog is registered once, and existing build settings are unchanged apart from the two app microphone usage descriptions. All image-catalog JSON and referenced files were checked; the four new PDFs decode with their original viewport dimensions and were visually inspected. New artwork callsites retain those dimensions and the designed layer composition. `git diff --check` passed. No third-party package, speech service, network client, or background-audio entitlement was added.

Apple API references: [recording](https://developer.apple.com/documentation/avfaudio/avaudiorecorder), [microphone permission](https://developer.apple.com/documentation/avfaudio/avaudioapplication), [audio files and PCM buffers](https://developer.apple.com/documentation/avfaudio/avaudiofile), [interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions).

### Xcode and device checklist

1. Build with the retained iOS 26.5 deployment target. Confirm the new controller/test file and four image assets appear in Xcode. Verify the built app's Info contains the microphone usage description in both build configurations. Run `XiaoLiaoTests`, including `ConversationAudioTests`; retry the UI suite when its runner can initialize.
2. Launch a conversation: there must be no microphone prompt until Record is tapped. Deny permission, confirm the explanation and Settings link, then grant permission and retry. Keep a working keyboard path when permission/input hardware is unavailable.
3. Record a distinct sentence, Pause, and tap the green waveform to preview it. Tap again to pause playback. Resume recording and say a second sentence; Pause and confirm playback contains both sentences in order with no speech lost or duplicated. Repeat pause/resume more than once.
4. Send while recording and while paused. Confirm exactly one green “语音消息 · [duration]” bubble is appended, its Play action plays the actual clip, the inline timeline advances, and no fake transcript, translation, or AI reply appears. The original fixture playback must remain disabled.
5. Send a typed reply and switch composer modes: previously sent voice/typed colors must stay fixed. Only the latest learner message offers Edit. Re-record the latest audio; cancel via keyboard or navigation and confirm the original still plays. Then send a replacement and confirm the same message is updated once and retained in history.
6. Switch history entries and settings; committed recordings must remain playable in their own entry. Start New Conversation; previous entries stay intact. Unsent recordings/replacements must be discarded on keyboard switching, history/settings navigation, or leaving the feed, including while permission or file processing is pending.
7. Background/lock the phone during recording and playback; test an incoming interruption and disconnecting headphones. Audio must stop and must not restart automatically. Return and record/play again. Inspect for a stuck recording row, duplicate send, or a lost committed clip after an interruption or permission failure.
8. Compare the recording and playback layouts to `2:121`, `2:303`, and `2:432` on large/small iPhones, landscape, Dynamic Type, VoiceOver, and Reduce Motion. Confirm 44-point action targets and accessible duration/play/pause/resume/send labels.
9. Relaunch and confirm history resets. Recordings are temporary current-run data; persistence is milestone four. Physical-device microphone/output behavior still needs testing even if the simulator works.

Milestone-three source work stopped at its boundary. The user subsequently authorized milestone four A while microphone testing remains pending until later. Open runtime questions: actual microphone/input routing on the user's cloud Mac, physical-device interruption behavior, and visual/accessibility comparison in Xcode. Speech recognition and live partner audio remain future integration work.

## Milestone 4 A — local persisted history

Authorized 2026-10-28: “Just the first part of Milestone 4.” Scope is local history persistence using the existing drawer; statistics and cloud/backend services remain out of scope. No new history screen, deletion/menu/search flow, or generated title is added.

- [x] Add a concrete SwiftData history store with one record per conversation and a versioned Codable payload. Update only the affected record on each save; keep audio bytes in separate files. Read text/settings metadata into the existing in-memory history list and use its existing native scrolling. No arbitrary conversation-count cap is imposed.
- [x] Persist conversation identity/title/prompt, committed text/fixture transcript/translation content, original sender/send method, and all three settings. Preserve newest-created-first ordering without reordering on settings/edit/reopen. Production starts with an empty history; the old B–J placeholder rows are retained only in unit/preview fixtures.
- [x] Copy committed recordings into `Application Support/XiaoLiao/Recordings` before writing their message references. Encode relative UUID filenames, resolve against the current installation's directory on load, and validate decoded file references. Temporary recording cleanup cannot remove committed clips.
- [x] Commit UI changes after successful saves. Failed text saves retain the draft/edit state, failed settings saves revert the selection, and failed audio saves retain the review clip for retry. Keep the previous message and recording on failed replacement. Reclaim superseded/unreferenced durable clips only after a successful complete load; failed/unsupported loads never trigger a reset or cleanup.
- [x] Restore the saved list on launch while opening New Conversation. Do not persist navigation, selected messages/details, unsent topic/text, draft settings, or unfinished recordings. New Conversation continues to clear only the draft, and reopening an entry clears transient UI.
- [x] Use native storage-failure alerts with a retry for initialization/read failures. Preserve missing-audio messages/settings and disable their Play action; report unavailable recordings rather than erase history or claim playback works.
- [x] Initialize persistence once at app entry; inject that shared model into root navigation. Keep normal unit tests and previews in memory, persistence unit tests in temporary directories, and Debug UI tests in separate UUID-named stores. UI relaunch tests reuse the same test store.
- [x] Add eleven focused persistence tests: empty first launch/transient drafts; full value/settings/send-method restoration; 300 conversations and stable order; audio copying/relative-path relocation; failed text/settings saves; failed audio replacement; missing audio; unsupported payload recovery; invalid clip paths; successful replacement/orphan cleanup; and initialization retry without data reset. Add a UI terminate/relaunch history/settings test and update the existing settings flow to create a second real conversation.
- [x] Register the two new Swift files once in the app/unit-test targets; retain build/signing/deployment/concurrency settings. Update both microphone usage descriptions to reflect durable local recording history. No third-party dependency, cloud capability, authentication, or AI integration is added.
- [ ] Build, run unit/UI tests, and perform force-quit/relaunch and audio checks in Xcode/on device.

Data is stored locally in the app's Application Support directory, using `History.store` and separate `Recordings/*.caf` files. This is persistence on the same installation, not a cross-device account or a remote backup feature. Earlier milestones never wrote history to disk, so their already-lost in-memory sessions cannot be migrated. Newly started conversations still use mock partner messages; persistence does not imply live AI.

### Milestone-four A validation

The simulator build command was attempted and failed with `xcodebuild: command not found` (exit 127). No successful compilation, SwiftData execution, unit/UI-test pass, simulator comparison, or microphone test is claimed. The earlier `Timed out waiting for AX loaded notification` UI-runner problem remains unresolved.

Static validation passed: the project parses; all 17 app, five unit-test, and three UI-test Swift sources are registered exactly once in their own targets; the asset catalog remains registered once. Existing build settings are unchanged except for the two updated microphone usage descriptions. `git diff --check` passed. No artwork, third-party dependency, cloud entitlement, statistics implementation, or network service was added.

Xcode/relaunch checklist:

1. Build with the unchanged iOS 26.5 deployment target. Confirm `ConversationHistoryStore.swift` and `ConversationPersistenceTests.swift` appear in Xcode and run the unit suite. Run the UI suite when its runner initializes; the tests must use isolated stores rather than clearing personal history.
2. On a fresh install, open history: only the existing “新对话” row should appear. Start two conversations with different prompts/settings, send/edit text, switch between entries, and verify independent content and stable ordering.
3. Force-quit and relaunch. Open history from New Conversation, reopen each saved entry, and verify prompts, edited messages, original voice/text colors, latest-message edit eligibility, and tone/vocabulary/reply-length selections. Unsent text, selected actions, and the previously open route must not return.
4. When microphone testing is available, record/send audio, relaunch, and play it from history. Record a replacement and cancel: the original must still play. Send a replacement, relaunch again, and verify the updated recording survives with the same message identity. Changing composer modes must not recolor older messages.
5. Start New Conversation, leave an unsent topic/text/recording, and relaunch. Saved entries must remain, and unfinished input must not be added to history. Merely opening history or changing draft settings must not create a saved conversation.
6. Check the persistence failure/unsupported-payload/missing-audio tests before considering recovery verified. No error path may delete the store or its referenced clips; failed saves must not appear successful. Check drawer scrolling and launch responsiveness with the 300-conversation fixture; no on-device performance benchmark has run here.

Apple references: [SwiftData persistence](https://developer.apple.com/documentation/swiftdata/preserving-your-apps-model-data-across-launches), [ModelContext save/rollback](https://developer.apple.com/documentation/swiftdata/modelcontext), [Application Support storage](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively).

Stop after local history persistence. No outstanding design choice blocks this implementation; runtime acceptance and the milestone-three microphone checks remain pending.

## Follow-up — inline system requests

Authorized after the user reviewed new Figma frames and confirmed the bottom-left head/arrow control toggles/cancels the mode. Requests are text only; system replies are always text. This replaces the earlier adjustment textbox/modal (`2:89`). The user explicitly waived compatibility work; no migration/reset UI or data deletion was added.

- [x] Inspect current design context/screenshots for `24:89`, `24:189`, and `24:236` using the Figma/SwiftUI workflow.
- [x] Enable the existing bottom-left control in voice/text composers. Arming focuses a light-blue text field; microphone and recording entry are unavailable. Tapping again cancels. After one successful send, restore the previous composer mode; failed/blank sends retain the draft and mode. Navigation clears an unsent armed request.
- [x] Store message purpose independently of original voice/text method and add a distinct system sender. Show user requests on the right in `#C4F3FE` with the existing black outline/tail; show replies on the left in `#4C75E1` with white text, four-point white outline, and no tail. Use scaled 24-point system text. Normal message appearance remains unchanged.
- [x] Add two deterministic demo requests: “你能用更简单的词吗？” updates the local vocabulary setting to Simple; “当前对话设置是什么？” reports actual local settings. Replies include a visible “本地示例” marker. Other input receives an explicit placeholder, without changing settings or inventing a partner response. No AI/network service is integrated.
- [x] Save both messages and any local setting change in one conversation snapshot. Retain purposes/senders across history/relaunch and preserve the draft on failure. Blue-message action rails remain unavailable because their selected/edit states are not designed.
- [x] Add three view-model tests, one persistence/failure test, and one UI toggle/send test. New cases cover text-only behavior, blank/cancel/one-message reset, local replies/settings, navigation cleanup, and saved purpose metadata. Tests are source-only until run in Xcode.
- [x] Add the two blue color assets and `#202020` request-text asset; reuse existing artwork/catalog membership. No Swift source file or Xcode project registration change is needed.
- [ ] Build/run tests and visually compare the blue composer/request/response in Xcode.

The build attempt failed with `xcodebuild: command not found` (exit 127). No compilation, test pass, or simulator rendering is claimed. Check the existing unit/UI suite on the Mac; the earlier AX runner timeout remains unresolved.

Static checks passed for the three color assets' JSON/exact hex values, shared artwork file references, and whitespace. The Xcode project is unchanged because all Swift changes/tests use existing registered files and the existing catalog contains the new colors. New request/reply geometry and reused tail/control layers were reviewed against the Figma context; effective rendering remains unverified until Xcode comparison.

Manual check: open a conversation, tap the bottom-left control, verify the blue composer/disabled microphone, type “你能用更简单的词吗？” and send using the keyboard. Confirm a light-blue request and dark-blue local-demo reply, normal composer restoration, and Simple vocabulary in conversation settings. Repeat with “当前对话设置是什么？” and arbitrary text. Reopen through history and relaunch to confirm both message types retain their appearance. Check small iPhones, keyboard avoidance, Dynamic Type, VoiceOver labels, and that previous practice messages keep their original colors. Do not treat the local demonstration as live AI understanding or changed generated partner speech.

## Follow-up — standalone data model definitions

Historical scope; superseded by the app-integration follow-up below.

Authorized scope: create message, grammar observation, and vocabulary observation models only. No app adoption, evaluator, statistics calculation, storage schema change, migration, or UI change.

- [x] Add `Models/Message.swift`: sender role, practice/system purpose, original modality, typed text/audio content, audio storage key/duration, optional transcription/confidence, timestamp, reply linkage, revision, and optional status.
- [x] Follow-up: define edits as separate immutable Message versions with unique record IDs/timestamps, a shared `logicalMessageID`, optional immediate `replacesMessageID`, increasing revision, and derived `isEdit`. Document that replies/observations refer to exact versions. Leave all running-app edit behavior and statistics policy unchanged.
- [x] Add `Models/GrammarObservation.swift`: shared metadata and applicable per-rule opportunities with category/subcategory codes, UTF-16 spans, outcomes, optional corrections/explanations/confidence. Derived counts are not duplicated in the model.
- [x] Add `Models/VocabularyObservation.swift`: shared metadata and word/phrase occurrences with surface text, optional lemma, spans, and grouped category assessments. This is not a complete token inventory or a separate record for every metric/word pair.
- [x] Add supporting `Models/ObservationMetadata.swift`: observation/message/conversation identity, source revision/text source, evaluation time, provenance, stable category codes, and explicit text-span units.
- [x] Register definitions under an explicit Models group and app Sources so they are visible/checkable in Xcode, without any runtime callsites. Existing conversation models/view model/store/views, fixtures, and tests are unchanged.
- [ ] Build the definitions in Xcode. No evaluator output, computed metric, or model persistence is claimed by this definitions-only task.

The existing ConversationMessage remains the running app's model. The proposed grammar/vocabulary containers represent one message-level evaluation each; no observation means not evaluated, while empty arrays mean no applicable entries were found. Applicable uncertain outcomes must be distinguished from errors in future statistics. Future consumers must validate IDs/revisions, ranges against the exact source text, positive revision numbers, nonnegative durations, and confidence values in 0...1; these declarations do not implement that processing. Topic-specific relevance remains a future context-dependent analysis.

Validation: project parsing/source-registration checks and `git diff --check` passed. All 21 app, five unit-test, and three UI-test Swift files are registered once; existing target/resource/build settings and running app/test source files are unchanged. The build attempt failed with `xcodebuild: command not found` (exit 127), so compilation remains unverified. No behavior tests were added for these declaration-only types.

## Follow-up — adopt canonical models in the app

Authorized: integrate the approved Message, GrammarObservation, and VocabularyObservation models into the actual conversation system. Keep the existing Figma UI, local fixtures, and audio interactions. No evaluator, metric calculation, backend, or statistics screen is added.

- [x] Replace ConversationMessage with canonical Message across fixtures, view-model state, actions, feed rendering, and persistence. New records include conversation identity, timestamps, sender/purpose, original modality, content, status, and exact-version reply links. Move contextual action definitions to MessageAction.swift.
- [x] Append immutable text/audio edit records with unique IDs/timestamps, shared logicalMessageID, immediate replacesMessageID, and incrementing revision. Retain every version; project only the latest version into its original feed position. Keep latest-user edit policy and original modality colors. Replies keep their original exact-version references.
- [x] Store grammar/vocabulary observations in each ConversationSession and restore them with history. Add validated record methods that replace only the evaluation of the same exact message version/type. Original-version observations survive edits; replacement versions start unevaluated. Do not run or simulate analysis automatically.
- [x] Validate session/message identity, linear edit chains, reply targets, evaluation eligibility/source/revision, confidence values, UTF-16 spans, and vocabulary surface text before commits. Invalid/failed writes leave existing state intact. Empty evaluated results remain distinct from no evaluation.
- [x] Persist canonical payload version 2 and relative audio keys. Resolve playback through durable or temporary storage. Retain recordings referenced by all historical versions, including replaced audio. Keep local audio-operation values separate from persisted Message.
- [x] Use Application Support/XiaoLiao/ConversationData-v2 for the new prototype store. Existing prototype history remains untouched in its previous directory and is not loaded or migrated, following the earlier compatibility waiver. No migration/reset UI is added.
- [x] Update focused state, audio, persistence, and UI-test sources for canonical IDs, immutable edits, stable feed rows, historical audio, exact-version observations/re-evaluation, Unicode/source validation, save failures, and relaunch. Tests use isolated temporary stores; they do not request real microphone permission.
- [x] Update explicit Xcode file references for MessageAction.swift, preserve Models source registration, and retain all existing build/signing/deployment/concurrency settings.
- [ ] Compile and run unit/UI tests in Xcode. Microphone/device acceptance remains pending.

Validation: the simulator build was attempted and failed with `xcodebuild: command not found` (exit 127). No compilation, executed test pass, SwiftData runtime result, or simulator rendering is claimed. Static checks passed: the project parses, all referenced files exist, and all 21 app/five unit-test/three UI-test Swift sources are registered exactly once in their targets. Build configurations and resource phases match both HEAD and the pre-integration project; `git diff --check` passed. No artwork, dependency, entitlement, or network service changed.

Xcode acceptance:

1. Build and run XiaoLiaoTests. The new store starts with an empty drawer; create conversations for this format. Earlier prototype history remains on disk but is not shown.
2. Edit the latest learner message more than once. Confirm a single visible row stays in position, retains its spoken/written color, and reopens with the newest text. Only the latest learner message may be edited, including after a partner reply; a newer blue system request removes older practice-message edit eligibility.
3. Send typed/system messages, change settings, switch history entries, and relaunch. Confirm exact content, local system replies/settings, colors, and ordering survive. Unsent input and selection must clear as before.
4. When microphone testing is possible, record/send, re-record the latest audio, cancel/retry, relaunch, and play the latest recording. Both immutable version references/files must remain stored. Confirm failed saves retain the unsent replacement and original audio.
5. Observation integration currently has no user-facing control. Use the unit cases for source/revision/span validation, original-versus-edit result retention, re-evaluation, relaunch, and failed writes. Do not expect automatic grammar/vocabulary feedback or statistics yet.

## Follow-up — statistics data and extraction

Authorized: add the discussed models and extraction code, with no grammar/clause evaluation or statistics UI yet. Tense consistency is removed from this milestone. Every submitted learner original/edit counts as a full practice attempt; word forms remain separate, and vocabulary dates represent first observed use.

- [x] Add MessageTextAnalysis for complete ordered word occurrences, sentence spans, exact-version metadata, normalization policy, and optional clause count/provenance. Persist/upsert analyses with the existing conversation payload and restore them per session. Empty results and missing results remain distinguishable.
- [x] Add ConversationStatisticsSummary, PracticeStatistics, DailyStatisticsSummary, StatisticsSnapshot, StatisticsConfiguration, GrammarMetricSummary, and VocabularyHistoryEntry value models. Snapshots are Codable and rebuildable from persisted inputs, with no duplicate authoritative counters or stale-cache workflow.
- [x] Add explicit Message origin: interaction versus fixture. Count complete learner practice records only, including every edit. Actual edits of a fixture become learner interactions. Preserve origin during audio relocation. Unknown older provenance stays excluded, while history remains readable.
- [x] Add four typed grammar category codes and correct/incorrect/uncertain aggregation. Unknown/unscored rates remain nil; no tense-consistency metric, grammar evaluator, confidence threshold invention, or fabricated assessment is added.
- [x] Add LocalTextAnalyzer using Apple Natural Language word/sentence segmentation for available text or supplied transcripts. Preserve raw spans, lowercase word forms, normalize apostrophes, and exclude punctuation/numerals/emoji/Chinese-only units. Run/runs/running remain separate. The local extractor does not infer clauses, judge grammar, or transcribe recordings. Sentence segments are not a claim of grammatical completeness.
- [x] Add StatisticsCalculator for sentence/clause totals, matching-coverage clauses-per-sentence ratios, distinct forms, first-use history/new-word counts, linear sliding-window MATTR, per-conversation/overall/day summaries, and half-open date ranges. MATTR uses available analyzed words in submission order and includes repeated edits; below-window scores remain nil. Initial window 50 is configurable, not a fixed product requirement.
- [x] Build global first use before reporting filters; attribute delayed analysis to message submission dates. Rebuilding/re-evaluation never appends duplicate practice counts. Retain coverage counts so incomplete audio/analysis never silently looks fully evaluated. Daily output includes only dates with eligible attempts.
- [x] Expose recordTextAnalysis and async statisticsSnapshot on the view model. Captured Sendable session values are calculated away from the UI actor. No automatic collection, lifecycle refresh, stats-button change, new screen, AI call, or third-party dependency is added.
- [x] Retain the existing payload version/directory. New analysis arrays default empty when decoding prior payloads; missing origin remains unknown. No data reset or speculative migration is needed. Add each of five new app files and the new test file exactly once to explicit Xcode groups/Sources.
- [x] Add thirteen focused statistics tests for hand-calculated MATTR, all-version counting and exclusions, per-version grammar aggregation, uncertain denominators, partial/empty coverage, first-use/date filtering, chronological corpus aggregation, local tokenization, bad inputs, persistence/read-only failure, and older payload decoding. These are test sources, not an executed pass.
- [ ] Compile/run XiaoLiaoTests in Xcode, including StatisticsTests and existing conversation/audio/persistence regressions. Check physical-device performance separately before promising timing or battery behavior.

Usage for future collection/UI integration: explicitly run LocalTextAnalyzer.analyze(message), pass an available result to recordTextAnalysis, and request await statisticsSnapshot(configuration:interval:calendar:). Grammar observations and optional ClauseAnalysis must come from separately implemented evaluators. Current sends do not automatically collect those results. Per-message analyses are durable; summary/word-inventory snapshots are calculated on request and may be encoded by a future cache owner if needed. Rebuilding is currently the freshness strategy, so no lifecycle dirty marker is necessary yet.

Validation: the simulator build command was attempted and failed with `xcodebuild: command not found` (exit 127); there is no Swift compiler in this workspace. No compilation, test pass, Natural Language runtime behavior, SwiftData runtime result, or device benchmark is claimed. Static project checks passed: all 26 app/six unit-test/three UI-test Swift sources are registered exactly once, referenced files exist, and build configurations/resource/framework phases match the pre-change project. `git diff --check` passed. Artwork, screens, capabilities, signing, deployment and concurrency settings are unchanged.

Xcode checks: run the unit suite; confirm new files appear under Models and Features/Statistics. Verify saved conversations/settings/audio still reopen, edits keep their prior visual behavior, and stats controls remain unavailable. StatisticsTests supplies analysis fixtures and exercises the new calculator; there is no user-facing statistics flow to manually test yet. For production collection, choose the MATTR window/short-sample presentation and sentence/clause rubric before building the charts.

Apple references: [Natural Language tokenization](https://developer.apple.com/documentation/naturallanguage/tokenizing-natural-language-text), [NLTokenizer](https://developer.apple.com/documentation/naturallanguage/nltokenizer). MATTR reference: [Covington and McFall](https://www.tandfonline.com/doi/abs/10.1080/09296171003643098).

## Follow-up — overall statistics dashboard

Authorized: implement overall user statistics, with flexible layout retaining the app’s cream paper/brown/green styling. Current-conversation statistics remain out of scope. The latest category list restores tense consistency, superseding the earlier omission; calculation version is now practice-statistics-v2.

- [x] Enable the existing stats artwork control on New Conversation and the feed. Both routes open the same all-history dashboard. Root owns navigation; persistent Back returns to the previous screen without clearing the conversation or New Conversation prompt. Existing recording/system-draft navigation cleanup remains in force.
- [x] Add StatisticsDashboardModel for async loading/failure/retry, category selection, daily chart presentation, calendar date domains, and integer vocabulary axes. Ignore stale async completions. An unreadable history store now throws from statisticsSnapshot even after its alert has been dismissed, so the UI cannot mistake a read failure for empty history.
- [x] Add five aligned horizontal accuracy bars (verb tense, tense consistency, articles, prepositions, subject–verb agreement) on a 0–100% scale. Make entire rows selectable and accessible, including zero/unknown cases, with an outlined selected state and percentage/unknown labels. Below, show the chosen category’s daily accuracy line.
- [x] Use Swift Charts for grammar/MATTR lines and daily newly-observed-word bars. Use fixed accuracy/MATTR bounds, calendar-day timestamps, explicit axis labels, single-point marks, and separate line series across unknown/missing dates. Daily rates are based on that day’s opportunity counts; no daily averaging produces overall proficiency.
- [x] Add the two-column activity table for sentences, clauses, and clauses per sentence. Preserve unknown versus measured-zero values, display evaluation/text/clause coverage, and explain the matched denominator for partial clause analysis. No grammar/clause producer, fake live scores, or automatic analysis collection is added.
- [x] Reuse paper texture/colors/system type and original Back artwork. Cards and plots scale with Dynamic Type; the horizontal comparison can scroll at accessibility sizes rather than truncating category names. Keep action targets at least 44 points and expose selected states/values. No new third-party dependency, tab, filter, sheet, capability, asset, or current-conversation dashboard is introduced.
- [x] Add populated/empty Xcode previews with DEBUG-only, explicitly fabricated sample observations. UI tests can opt in only alongside a unique isolated-store UUID; the samples stay in memory and never enter normal persistent history or Release builds.
- [x] Add seven dashboard unit-test sources for empty/zero/gap handling, category selection, loading retry, stale completion, unreadable storage, and preview inputs; add three UI flows for empty/root navigation, populated selection/table, and feed return. Extend the statistics taxonomy test to all five categories. No executed test pass is claimed.
- [x] Register the three new app files and new unit file once in explicit Xcode groups and Sources. Retain all signing/deployment/concurrency/resource settings and prior uncommitted statistics work.
- [ ] Build/run tests and inspect actual SwiftUI/Charts rendering on the Mac. No Apple SDK is available here.

Validation: xcodebuild was attempted and failed with command not found (exit 127). No compilation, unit/UI-test pass, simulator screenshot, chart interaction, or device-performance result is claimed. Static checks passed: the project parses, referenced files exist, and all 29 app/seven unit-test/three UI-test Swift sources are registered once. Build configurations, resource phases, and framework phases match both the pre-dashboard and pre-statistics baselines; git diff --check passed. The only framework addition is a source import of Apple Charts, linked by Swift’s normal framework autolinking.

Mac acceptance:

1. Build the existing iOS 26.5 scheme. Run StatisticsTests, StatisticsDashboardTests, and existing unit regressions. Retry UI tests when the known AX runner initialization issue permits.
2. Tap the stats icon on New Conversation, select a different grammar row, and return. The original prompt/start state must remain. Repeat from an open conversation and verify Back returns to the same feed/messages/settings. No current-conversation statistics screen is present.
3. With normal unanalysed data, expect unknown bars, empty plots, and dashes, not fabricated scores. Evaluation/collection is still pending. Open the named populated/empty previews in StatisticsPreviewData.swift to inspect real chart layouts with explicit sample data.
4. In populated preview/debug UI tests, select each of the five bars, confirm its title/trend changes, check 0–100%/0–1 axes, verify isolated points and gaps, inspect the vocabulary bars and activity table, and verify integer new-word ticks. Sample data must not appear in normal app history.
5. Check small/large iPhones, landscape, Dynamic Type including accessibility sizes, VoiceOver row selection and chart points, Reduce Motion, scrolling, and that Back remains reachable while scrolled. Verify failure/retry preserves history rather than displaying a false empty state.

Apple references: [Swift Charts](https://developer.apple.com/documentation/Charts/Chart), [LineMark series](https://developer.apple.com/documentation/charts/linemark), [chart accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/charts).

## Follow-up — connect committed text to statistics

Authorized: implement the recommended next step and update Markdown documentation. Automatically collect local word/sentence structure from committed learner text and edits; persist it and populate the existing overall dashboard. Keep grammar/clause evaluation, speech recognition, AI integration, and current-conversation statistics out of scope.

- [x] Save the submitted message/edit before queueing analysis. Clear the sent draft and return without awaiting extraction. Include every text-backed learner edit as its own practice attempt; retain original modality and exact-version links.
- [x] Add an owned sequential analysis worker to ConversationViewModel. Run the concrete LocalTextAnalyzer off the UI actor, deduplicate queued/in-flight exact message IDs, and merge valid results into the latest owning history entry on the main actor. Preserve newer messages/settings, unsent input, navigation, selection, and existing storage alerts. Inactive sessions can receive their results without becoming active.
- [x] Infer durable pending work from committed eligible text missing its analysis. Retry on initialization/successful history loading, app foregrounding, and statistics opening. Do not poll or depend on app termination. No separate job store/schema or migration is introduced.
- [x] Keep failed/nil/misidentified/invalid extraction and analysis-write failures separate from chat-send success. Preserve the submitted message and leave its analysis missing for later retry. Skip already supplied results so a late automatic job cannot erase richer clause/evaluator data.
- [x] Make statisticsSnapshot retry and await queued text work before producing fresh counts. Keep cancellation local to a dashboard request; committed-message analysis continues. Refresh the dashboard after foreground retries. Existing coverage/empty states still distinguish unknown grammar/clauses or insufficient MATTR samples.
- [x] Exclude fixtures, system/partner exchanges, unknown-origin/status history, failed/pending sends, unsent drafts, and real audio from automatic collection. Text-backed spoken edits retain their color/modality and use their explicit text/transcript source. No speech recognition, microphone, playback, grammar evaluator, clause parser, AI call, new chart, or new interaction is added.
- [x] Adjust the debug-only preview gap to an untranscribed audio record so it remains a legitimate gap under automatic text collection; preserve the existing isolated-fixture guard and production-data exclusions.
- [x] Add nine focused pipeline tests for real send/edit/statistics flow, in-flight deduplication and conversation switching, failures/retry, nil/wrong results, relaunch/read-only-save recovery, failed chat saves, eligibility exclusions, richer-result preservation, and dashboard cancellation. Add one UI send-to-statistics/relaunch flow. Tests use real local tokenization, controlled async gates, and temporary stores; no actual microphone or AI is invoked.
- [x] Update README.md with current capabilities, counting rules, expected MATTR/unknown behavior, and Mac validation instructions; update these conventions/plan. Register the new unit-test file once in Xcode without changing build settings.
- [ ] Build and run the unit/UI suites in Xcode; no Apple SDK is available in this workspace.

Runtime behavior: typed messages and text edits are persisted immediately, then receive structural analysis. Opening overall statistics waits for pending work and displays sentence totals, first-observed word counts/history, and MATTR once enough words exist. Grammar percentages, clause totals, and clauses per sentence remain unknown without separately supplied evaluations. Existing explicit analyses are retained, not automatically re-evaluated. Previously saved eligible, explicitly tagged text can be caught up on launch; older unknown-provenance records remain excluded without inventing history.

Validation: the generic iOS Simulator build was attempted and failed with `xcodebuild: command not found` (exit 127). No compilation, executed test pass, Natural Language runtime result, SwiftData runtime result, simulator interaction, or timing benchmark is claimed. Static checks passed: the project parses, referenced files exist, and all 29 app/eight unit-test/three UI-test Swift sources are registered once in their own targets. Build configurations, resource phases, and framework phases match both HEAD and the pre-change project. git diff --check passed. No deployment/signing/concurrency setting, asset, dependency, capability, or storage version changed.

Mac acceptance:

1. Build the unchanged iOS 26.5 scheme. Run TextAnalysisPipelineTests, StatisticsTests, StatisticsDashboardTests, and existing conversation/persistence/audio regressions. Run UI tests when the prior AX runner issue permits.
2. Start a conversation and type a few English sentences. Open overall statistics immediately: sentence totals/new words should populate after the brief local-processing state, while grammar and clause values stay unknown. Short samples legitimately leave MATTR blank; use at least 50 analyzed words on a day for that day's point.
3. Edit the latest text. Both versions should contribute fully; the feed still displays a single latest-version row with its original modality color. Previously observed forms keep their first-use date; newly introduced forms appear on the edit’s submission date.
4. Send then quickly switch conversations or leave an unsent draft elsewhere. When analysis completes, only its original conversation receives the result; the newly active messages/settings/draft stay unchanged. Cancel opening statistics and reopen to verify message processing was not cancelled.
5. Force-quit/relaunch and reopen statistics. Saved inputs and analyses should survive without duplicate counting. A committed message killed before analysis/save should be recovered from missing work. Confirm the read-only/failure tests retain messages and that later writable relaunch fills the missing results.
6. Verify system exchanges/fixtures/untranscribed recordings do not generate text statistics. Keep the existing recording/playback behavior intact; there is no new permission prompt. Check UI responsiveness on a real device before promising performance.

## Milestone 4 B remainder — current-conversation statistics UI (future; not authorized)

The overall dashboard is implemented in the follow-up above. Implement current-conversation statistics only after a separate request. Acceptance: statistics match defined sample calculations and the app/tests build.

## Milestone 5 A — real text conversations (prepared; deployment/Mac testing pending)

The user selected the OpenAI/Cloudflare approach, confirmed initial testers are outside mainland China, created `xiaoliao-api.leeharriswilliamson.workers.dev`, and saved the OpenAI secret. This increment prepares the backend and connects the normal app's text conversation flow. Existing offline fixtures remain isolated in tests/previews. No deployment, real provider call, speech service, evaluator, or current-conversation statistics UI has been performed/added.

- [x] Add a dependency-free module Worker, Wrangler configuration, and SQLite-backed Durable Object binding/migration. `/health` is free; `/v1/conversations/respond` requires a separate private-beta token. Fail closed when configuration/authentication is missing. Ignore client-supplied provider/model/tool fields and validate message roles, target IDs, settings, body size, and context bounds.
- [x] Call OpenAI Responses using the server secret, initially `gpt-6.1-terra`, with `store: false`, bounded output, server-owned versioned instructions, strict structured output, sanitized errors, and a 35-second upstream timeout. Treat blue system-purpose messages as user data, not privileged provider roles. Parse assistant output after optional reasoning items; reject refusals/incomplete/malformed replies.
- [x] Enforce beta-wide limits of 10 new attempts/minute and 200/UTC-day, including failed provider attempts. Cache completed output by immutable request ID/hash for 24 hours, reject ID/body conflicts and simultaneous duplicates, and reclaim expired output on hourly alarms. Retain no input prompt/history in the cache. Interrupted calls/cache expiry can cause another paid attempt; no exactly-once billing guarantee is claimed.
- [x] Add a provider-independent Swift request/response/service and persisted PendingConversationReply snapshot. Normal app entry explicitly injects the live URLSession generator; isolated UI tests/previews remain offline. Debug reads only a separate beta token from the local Xcode Run environment. Never place the OpenAI key on-device; Release has no embedded beta credential.
- [x] Start live conversations empty and request an actual opening partner reply from the prompt/settings; start in the text composer. Atomically save learner text/edit plus pending request before calling the backend. Keep local structural analysis independent. Store generation model/prompt version and exact reply targets; keep older immutable edit versions and earlier replies intact.
- [x] Reuse Figma `2:505`'s outlined speech oval/ellipsis only while a request runs. Render written partner replies on the left using existing text bubbles; retain modality-based learner colors and action rails. Add inline failure/retry/dismissal and input-validation alerts without a new screen. Block sends/edits/recording until pending work completes or a failed wait is dismissed.
- [x] Save reply/settings/pending removal atomically and merge into the CURRENT owning conversation, preserving local analyses, active drafts/navigation, and settings changed during the request. Blue requests receive one written system response and validated supported setting changes, with no extra partner reply. Recent blue exchanges inform subsequent topic/role behavior. No streaming or unlimited-context/profile-memory claim is made.
- [x] Persist the immutable ID/body across failed requests, navigation, and relaunch. Relaunch offers explicit recovery instead of automatically making paid calls. Failed local sends keep their draft and do not call the provider; failed reply saves keep the pending snapshot. Stable result IDs prevent duplicate bubbles.
- [x] Add 16 backend tests covering routing/configuration/authentication, input limits/target/role validation, prompt/schema construction, raw Responses parsing, system versus partner settings, refusal/failure sanitization, cache/conflicts/concurrent retries, quotas, failed-attempt accounting, and cleanup. These execute with mocked fetch/storage and no credentials or paid requests.
- [x] Add 12 focused Swift test sources for live opening/text/edit/statistics behavior, stable retries/deduplication, conversation switching, system changes/manual-control preservation, relaunch recovery, wrong identities, oversized drafts, failed local sends/reply saves, and bounded context/audio exclusion. Register the app/test files exactly once; expose backend/setup documentation in Xcode without adding them to build phases.
- [x] Update AGENTS/README and add `Docs/BACKEND_SETUP.md` with secrets, deployment, Debug configuration, acceptance checks, limits, and retention behavior. Preserve all previous local-analysis work and payload version 2; missing optional new fields decode without resetting history.
- [ ] Add Cloudflare's separate `XIAOLIAO_CLIENT_TOKEN` Secret, deploy the prepared Worker with Wrangler (including its binding/migration), and verify the live health route.
- [ ] Configure matching `XIAOLIAO_API_TOKEN` in the local Xcode Debug Run environment. Build/run Swift tests and perform the guide's live conversation/manual UI checks on the Mac.

Validation here: all 16 native Node backend tests passed with mocked upstream/storage; `node --check` passed. Static project checks passed for all 30 app/nine unit/three UI Swift files, correct target membership, existing referenced files, and unchanged build settings/resources/framework phases. The attempted generic iOS Simulator build returned `xcodebuild: command not found` (exit 127). No Swift compilation, Swift test pass, deployed Cloudflare runtime check, microphone acceptance, live OpenAI response, or actual SwiftUI comparison is claimed. Backend tests do not replace Wrangler/deployed integration or Xcode testing.

Deployment and Mac acceptance are in [BACKEND_SETUP.md](Docs/BACKEND_SETUP.md). Before public distribution, replace the Debug-only shared beta token with real account authentication/ownership and per-user quotas. Later increments can add reviewed grammar/clause evaluation and connect speech transcripts to the same message/statistics path; synthesized speech and pronunciation feedback remain separate future work.
