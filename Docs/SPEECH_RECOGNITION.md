# On-device recorded English transcription

This increment connects newly sent recordings and recorded replacements to the same partner-reply, grammar, and local statistics pipelines as written messages. Existing recordings remain untouched unless the user records a new replacement. It does not implement live word-by-word captions, transcription editing, translation, pronunciation scoring, or a new recording/review screen.

## Try it on your physical iPhone or iPad

Use a physical iPhone or iPad running **iOS/iPadOS 26.5 or later**, matching the unchanged deployment target. The MacBook remains suitable for development/playback, but microphone playback alone does not establish that a simulator supports Apple's speech models.

1. Sync the updated repository to your Mac and build the app in Xcode. Select your connected iPhone as the Run destination and use the existing signing configuration.
2. Keep the working Debug Run `XIAOLIAO_API_TOKEN` environment variable and launch from Xcode. This client-only feature needs **no Cloudflare redeployment or new secret**, assuming the already working conversation and grammar endpoints remain deployed.
3. Start a conversation, switch to voice, record a short English sentence such as `I like green tea.`, then use the existing Pause/Send row. Microphone permission is requested only when recording starts.
4. The sent recording is saved first. The existing loading oval now covers transcription as well as the subsequent partner response. First use may need network access to download the English model; the caption explains this. Voice audio itself stays local.
5. Expect the recognized text in the existing green learner bubble, then an actual text partner reply. Play must still use the original saved recording. Switching the composer must not change the bubble color. Opening overall statistics should show sentence/word/vocabulary results and, after successful grammar evaluation, scored grammar opportunities. The same message counts as ONE practice attempt.
6. Edit the most recent recording using the existing replacement-recording flow. A replacement is a new immutable message version with its own transcript, reply target, and analysis; both versions count fully. The original recording/transcript remains stored, and the feed displays the latest version.
7. Check a device with the English model already installed while offline: local transcription can complete, while partner/grammar network requests fail with their existing retry behavior. For first-use asset download failure, missing speech support, silence, or recognition failure, the recording remains saved/playable. Use the existing Retry row, or “暂不重试” to retain the audio and continue without a reply. Editing the latest recording permits a new replacement.
8. Send then switch conversations or leave an unsent draft elsewhere. The result and reply must stay with their original conversation. Backgrounding cancels current recognition; recorded audio survives and explicit Retry recovers it. Relaunch resumes only queued/unattempted jobs; interrupted/failed jobs wait for Retry. Transcription failures must not create grammar mistakes, fake replies, duplicated practice attempts, or erase history.

If all local engines report unavailable on a simulator, use the physical iPhone to validate speech. Availability depends on the actual device and English model support. Do not replace unavailable speech with fabricated transcripts or silently upload the recording.

## Implementation and data

`LocalSpeechTranscriber` uses `SpeechAnalyzer` with `SpeechTranscriber` and an English-US locale mapped to a supported locale. When that engine/device/locale is unavailable, it uses `DictationTranscriber.longDictation` if supported. Both are on-device modules; `SFSpeechRecognizer` and its optional server processing are not used. The newer modules do not require the older speech-server authorization prompt. The microphone usage description now covers local transcription and use of the resulting text for conversation/statistics.

`AssetInventory` installs required English assets when needed and the system retains them for reuse. Installation can require connectivity and available storage. Cancelling a download cancels its progress; cancelling recognition also cancels result collection and finishes the analyzer. Only finalized results are concatenated. Confidence remains nil; this increment does not invent a confidence value or infer pronunciation accuracy. Empty transcripts and transcripts longer than the existing 4,000-character API limit remain failed/recoverable, not silently truncated.

A newly submitted recording is promoted to durable storage together with a `SpeechTranscriptionJob`. Jobs reference exact message IDs/revisions, not absolute filenames, so audio-file promotion/sandbox relocation cannot break them. Only app entry injects the concrete recognizer; tests/previews remain offline unless they explicitly inject a test closure. A single owned worker serializes local recognition across conversations. It saves attempted state before starting, re-finds current owning history after awaiting, and validates the final transcript before committing.

Recognition enriches the existing message's transcription metadata while preserving `id`, `logicalMessageID`, `createdAt`, `revision`, audio reference/duration, original modality, and reply link. It is not a learner edit and must not create a second practice attempt. The commit clears the transcription job and creates the partner request/grammar job atomically before any paid request is started. Structural analysis uses `speechTranscription` as its source; recorded original/edit versions remain separate practice attempts under existing counting rules. The grammar backend already accepts this source, so its deployed contract is unchanged.

The composer waits for transcription/reply, using the same wait/retry/dismiss behavior as typed chat. Navigation remains available. Failed or interrupted transcription never sends an empty message to the partner, never manufactures an evaluation, and never deletes the clip. Dismissal retains the audio-only practice record; it does not backfill it later. Save failures retain the recording/job and do not launch downstream paid calls. Existing history decodes missing `pendingTranscription` as nil under the unchanged version-2 payload. Existing audio filenames and all immutable edit versions remain retained.

Audio never goes to Cloudflare, OpenAI, or Apple's speech servers. The recognized text does go through the already authorized conversation/grammar endpoints. Transcription errors can affect replies and grammar judgments; ASR output is not a pronunciation assessment. Those quality checks remain separate from wiring the feature.

## Validation status

Ten injected speech-pipeline XCTest cases cover identity/counting, audio/playback retention, retries, late conversation results, recorded edits, promoted-file/relaunch recovery, queued versus interrupted work, cancellation, invalid/empty/oversized transcripts, failed initial saves, and no old-audio backfill. They write local CAF fixtures and use injected transcript/reply/evaluation closures; they do not request a microphone, install models, or call paid APIs.

This workspace has no Apple SDK, so actual Swift compilation, Speech framework execution, model installation, audio accuracy, physical-device playback, and SwiftUI rendering must be checked on the Mac/iPhone. Keep the prior user-reported microphone/playback and live grammar successes separate from acceptance of this new transcription feature.

Official Apple references: [SpeechAnalyzer and recorded-file transcription](https://developer.apple.com/documentation/speech/speechanalyzer), [SpeechTranscriber availability](https://developer.apple.com/documentation/speech/speechtranscriber), [local DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber), [model assets](https://developer.apple.com/documentation/speech/assetinventory), [permission requirements](https://developer.apple.com/documentation/speech/asking-permission-to-use-speech-recognition), [WWDC implementation overview](https://developer.apple.com/videos/play/wwdc2025/277/).

## Partner reply playback

The Apple built-in voice follow-up reads complete partner **text** replies aloud on demand. Select the partner bubble and tap its existing Play action. Tap again to pause, then again to resume. Once finished, Play starts the reply again. Replies do not autoplay. Existing saved partner text replies work too; the original fixture audio without a recording remains unavailable.

Speech uses `AVSpeechSynthesizer`, the system `en-US` voice and default speech rate. It shares the controller/audio session with real recording playback, without creating or persisting a synthesized audio file. It does not change the reply's ID, written modality, content, timestamp, statistics or history. No new permission, backend deployment, secret, or paid speech endpoint is required. If no English voice is available, the existing audio alert explains the failure; the text remains readable.

On the physical iPhone/iPad, check:

1. Select a live partner text reply, tap Play, pause mid-sentence, resume, let it finish, then replay. The existing action highlights while active and VoiceOver labels it “暂停播放”. The original text bubble stays visible; no recording duration or fake progress card is added.
2. Play a different reply while speech is active. Only the new reply should speak. Preview/play a learner recording and then play a partner reply; these audio sources must replace each other.
3. Start recording during partner speech. Speech must stop before microphone permission/recording, and must not resume when recording ends. Review/Pause/Send and learner recording playback must still work. Partner Play remains unavailable while a recording draft exists.
4. While speech is active or paused, open history/settings/statistics, switch conversations, or background/lock the app. Speech must stop. Also check an incoming audio interruption and headphone disconnection. Returning must not resume it automatically.
5. Blue system exchanges stay text-only; typed learner messages do not gain synthesized playback. Repeat playback and reopening history must not create messages/edits or change practice statistics. A failed voice/audio-session attempt must retain the reply and permit another tap to retry.
6. Check speaker and headphones, offline playback with an available English voice, larger Dynamic Type, and VoiceOver action/selection announcements. Voice availability and voice quality depend on the device/system voice assets.

Two focused XCTest cases cover saved-text/history eligibility, exclusions for system/learner/unfinished messages, and blocking playback during a microphone request without invoking native speech. The live-reply test also checks Play availability and absence of automatic playback or fabricated recording data. Actual synthesis, pause/resume, audio routing and lifecycle checks require Xcode and physical hardware; these tests do not replace them.

Apple references: [AVSpeechSynthesizer](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer), [application audio-session ownership](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/usesapplicationaudiosession), [speech delegate lifecycle](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate).
