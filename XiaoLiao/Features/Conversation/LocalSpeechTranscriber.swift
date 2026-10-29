import AVFoundation
import Foundation
import Speech

/// Only newly sent recordings get a job. Old audio history is never backfilled.
nonisolated struct SpeechTranscriptionJob: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case queued, attempted, failed }
    let id: String
    let messageID: String
    let messageRevision: Int
    let requestsPartnerReply: Bool
    var state: State = .queued
    var failureMessage: String?

    init(message: Message, requestsPartnerReply: Bool) {
        id = UUID().uuidString
        messageID = message.id
        messageRevision = message.revision
        self.requestsPartnerReply = requestsPartnerReply
    }
}

nonisolated enum SpeechTranscriptionError: Error, LocalizedError, Sendable {
    case unsupported, modelUnavailable, recordingUnavailable, noSpeech, tooLong, interrupted, recognitionFailed

    var errorDescription: String? {
        switch self {
        case .unsupported: "此设备暂不支持英语离线识别。请使用支持的 iPhone，或改用键盘输入。"
        case .modelUnavailable: "英语识别模型暂未就绪。首次使用需联网下载，请检查网络和储存空间后重试。"
        case .recordingUnavailable: "录音文件暂不可用，无法转写。已有消息仍已保留。"
        case .noSpeech: "没有识别到可用的英语语音。录音已保留，可以试听后重试或重新录制。"
        case .tooLong: "识别出的文字超过 4000 字符。录音已保留，请缩短后重新录制。"
        case .interrupted: "转写已中断，录音已保留。请重试。"
        case .recognitionFailed: "暂时无法转写这段录音。录音已保留，请重试。"
        }
    }
}

/// Apple on-device engines only. Model assets can download; recorded audio is never uploaded.
nonisolated struct LocalSpeechTranscriber: Sendable {
    static func transcribe(_ clip: LocalAudioClip) async throws -> Message.Transcription {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: clip.url.path) else { throw SpeechTranscriptionError.recordingUnavailable }
        let english = Locale(identifier: "en-US")
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: english) {
            let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
            return try await recognize(clip, module: transcriber) {
                var text = ""
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    text += String(result.text.characters)
                }
                return text
            }
        }
        if let locale = await DictationTranscriber.supportedLocale(equivalentTo: english) {
            // DictationTranscriber supports ONLY on-device models, never server fallback.
            let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
            return try await recognize(clip, module: transcriber) {
                var text = ""
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    text += String(result.text.characters)
                }
                return text
            }
        }
        throw SpeechTranscriptionError.unsupported
    }

    private static func recognize(_ clip: LocalAudioClip, module: any SpeechModule,
                                  collect: @escaping @Sendable () async throws -> String) async throws -> Message.Transcription {
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await withTaskCancellationHandler {
                    try await installation.downloadAndInstall()
                } onCancel: {
                    installation.progress.cancel()
                }
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw SpeechTranscriptionError.modelUnavailable
        }
        try Task.checkCancellation()
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: clip.url) }
        catch { throw SpeechTranscriptionError.recordingUnavailable }
        let analyzer = SpeechAnalyzer(modules: [module])
        let collector = Task { try await collect() }
        return try await withTaskCancellationHandler {
            do {
                if let lastSample = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let rawText = try await collector.value
                let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard !text.isEmpty else { throw SpeechTranscriptionError.noSpeech }
                guard text.utf16.count <= 4000 else { throw SpeechTranscriptionError.tooLong }
                return Message.Transcription(text: text, confidence: nil)
            } catch {
                await analyzer.cancelAndFinishNow()
                collector.cancel()
                _ = await collector.result
                if Task.isCancelled { throw CancellationError() }
                if let error = error as? SpeechTranscriptionError { throw error }
                throw SpeechTranscriptionError.recognitionFailed
            }
        } onCancel: {
            collector.cancel()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}
