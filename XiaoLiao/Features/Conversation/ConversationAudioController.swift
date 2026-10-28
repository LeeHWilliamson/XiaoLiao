import AVFoundation
import AudioToolbox
import Foundation
import Observation

/// Drafts use temporary files; committed recordings are copied into Application Support.
nonisolated struct LocalAudioClip: Equatable, Sendable, Codable {
    let url: URL
    let duration: TimeInterval

    var durationLabel: String { "\(max(1, Int(duration.rounded(.up))))秒" }

    static let directoryKey = CodingUserInfoKey(rawValue: "XiaoLiao.recordingsDirectory")!
    private enum CodingKeys: String, CodingKey { case filename, duration }

    init(url: URL, duration: TimeInterval) {
        self.url = url
        self.duration = duration
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let filename = try values.decode(String.self, forKey: .filename)
        let duration = try values.decode(TimeInterval.self, forKey: .duration)
        guard filename.hasSuffix(".caf"), UUID(uuidString: String(filename.dropLast(4))) != nil,
              duration.isFinite, duration > 0, duration < Double(Int.max) / 2,
              let directory = decoder.userInfo[Self.directoryKey] as? URL else {
            throw DecodingError.dataCorruptedError(forKey: .filename, in: values, debugDescription: "Invalid local recording reference")
        }
        self.url = directory.appendingPathComponent(filename)
        self.duration = duration
    }

    func encode(to encoder: any Encoder) throws {
        guard url.pathExtension == "caf", UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil,
              duration.isFinite, duration > 0, duration < Double(Int.max) / 2 else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Invalid local recording reference"))
        }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(url.lastPathComponent, forKey: .filename)
        try values.encode(duration, forKey: .duration)
    }
}

@MainActor
@Observable
final class ConversationAudioController: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    enum RecordingState: Equatable {
        case idle, requestingPermission, recording, processing, review
    }

    struct Issue: Equatable {
        let message: String
        var offersSettings = false
    }

    private(set) var recordingState: RecordingState = .idle
    private(set) var duration: TimeInterval = 0
    private(set) var level: Double = 0
    private(set) var reviewClip: LocalAudioClip?
    private(set) var playbackID: String?
    private(set) var playbackProgress: Double = 0
    private(set) var isPlaying = false
    var issue: Issue?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var currentSegment: URL?
    @ObservationIgnored private var segments: [URL] = []
    @ObservationIgnored private var completedDuration: TimeInterval = 0
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var sessionIsActive = false
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let permissionRequest: @MainActor () async -> Bool

    // No history is persisted. Clear this app's previous-run scratch files once per launch.
    private static let runDirectory: URL = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("XiaoLiaoRecordings", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        return root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }()

    init(directory: URL? = nil, permissionRequest: (@MainActor () async -> Bool)? = nil) {
        self.directory = directory ?? Self.runDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.permissionRequest = permissionRequest ?? { await AVAudioApplication.requestRecordPermission() }
        super.init()
    }

    var hasDraft: Bool { recordingState != .idle }
    var canSend: Bool { recordingState == .recording || recordingState == .review }

    @discardableResult
    func startRecording() -> Task<Void, Never>? {
        guard recordingState == .idle || recordingState == .review else { return nil }
        stopPlayback()
        issue = nil
        generation = UUID()
        let request = generation
        recordingState = .requestingPermission
        let task = Task { [weak self] in
            guard let self else { return }
            let granted = await permissionRequest()
            guard !Task.isCancelled, generation == request, recordingState == .requestingPermission else { return }
            permissionTask = nil
            guard granted else {
                cancelDraft()
                issue = Issue(message: "需要麦克风权限才能录音。请在系统设置中允许小聊使用麦克风。", offersSettings: true)
                return
            }
            beginSegment()
        }
        permissionTask = task
        return task
    }

    private func beginSegment() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            sessionIsActive = true
            let url = directory.appendingPathComponent(UUID().uuidString + ".caf")
            currentSegment = url
            let newRecorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            recorder = newRecorder
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            guard newRecorder.prepareToRecord(), newRecorder.record() else { throw AudioFailure.recording }
            recordingState = .recording
            startMeter()
        } catch {
            cancelDraft()
            issue = Issue(message: "无法开始录音。请检查麦克风是否可用，然后重试。")
        }
    }

    /// Close each segment before review so playback always reads a finalized file.
    /// Resuming records a new segment; joining keeps all previous speech intact.
    func pauseRecording() async {
        guard recordingState == .recording, let recorder, let url = currentSegment else { return }
        let request = generation
        let segmentDuration = recorder.currentTime
        recorder.delegate = nil
        recorder.stop()
        self.recorder = nil
        currentSegment = nil
        stopMeter()
        level = 0
        deactivateSession()
        if segmentDuration > 0.05 {
            segments.append(url)
            completedDuration += segmentDuration
        } else {
            Self.removeFile(url)
        }
        guard !segments.isEmpty else {
            cancelDraft()
            issue = Issue(message: "录音太短，请再试一次。")
            return
        }
        duration = completedDuration
        recordingState = .processing
        let inputs = segments
        let output = directory.appendingPathComponent(UUID().uuidString + ".caf")
        do {
            let actualDuration = try await Task.detached(priority: .userInitiated) {
                try Self.joinSegments(inputs, to: output)
            }.value
            guard generation == request, recordingState == .processing else {
                Self.removeFile(output)
                return
            }
            if let previous = reviewClip { Self.removeFile(previous.url) }
            reviewClip = LocalAudioClip(url: output, duration: actualDuration)
            duration = actualDuration
            recordingState = .review
        } catch {
            Self.removeFile(output)
            guard generation == request else { return }
            cancelDraft()
            issue = Issue(message: "录音未能保存，请重新录制。")
        }
    }

    func finishDraft() async -> LocalAudioClip? {
        let request = generation
        if recordingState == .recording { await pauseRecording() }
        guard generation == request, recordingState == .review, let clip = reviewClip else { return nil }
        return clip
    }

    /// Release the draft only after the conversation has actually been saved.
    func completeSend() {
        guard recordingState == .review else { return }
        reviewClip = nil
        cancelDraft()
    }

    func cancelDraft() {
        generation = UUID()
        permissionTask?.cancel()
        permissionTask = nil
        recorder?.delegate = nil
        recorder?.stop()
        recorder = nil
        stopPlayback()
        stopMeter()
        if let currentSegment { Self.removeFile(currentSegment) }
        segments.forEach { Self.removeFile($0) }
        if let reviewClip { Self.removeFile(reviewClip.url) }
        currentSegment = nil
        segments = []
        reviewClip = nil
        completedDuration = 0
        duration = 0
        level = 0
        recordingState = .idle
        deactivateSession()
    }

    func previewDraft() {
        guard recordingState == .review, let reviewClip else { return }
        togglePlayback(reviewClip, id: "recording-draft")
    }

    func togglePlayback(_ clip: LocalAudioClip, id: String) {
        guard recordingState == .idle || recordingState == .review else { return }
        issue = nil
        if playbackID == id, let player {
            if isPlaying {
                player.pause()
                isPlaying = false
                stopMeter()
                deactivateSession()
            } else {
                do {
                    try activatePlayback()
                    if player.currentTime >= player.duration { player.currentTime = 0 }
                    guard player.play() else { throw AudioFailure.playback }
                    isPlaying = true
                    startMeter()
                } catch { failPlayback() }
            }
            return
        }
        stopPlayback()
        do {
            try activatePlayback()
            let newPlayer = try AVAudioPlayer(contentsOf: clip.url)
            player = newPlayer
            newPlayer.delegate = self
            guard newPlayer.prepareToPlay(), newPlayer.play() else { throw AudioFailure.playback }
            playbackID = id
            playbackProgress = 0
            isPlaying = true
            startMeter()
        } catch { failPlayback() }
    }

    func stopPlayback() {
        player?.delegate = nil
        player?.stop()
        player = nil
        playbackID = nil
        playbackProgress = 0
        isPlaying = false
        if recordingState != .recording {
            stopMeter()
            deactivateSession()
        }
    }

    /// Interruptions never automatically restart the microphone or speaker.
    func interrupt() {
        let wasRecording = hasDraft
        cancelDraft()
        if wasRecording { issue = Issue(message: "录音已中断，未发送。请重新录制。") }
    }

    func discard(_ clip: LocalAudioClip) { Self.removeFile(clip.url) }

    private func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio)
        try session.setActive(true)
        sessionIsActive = true
    }

    private func deactivateSession() {
        guard sessionIsActive else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        sessionIsActive = false
    }

    private func failPlayback() {
        stopPlayback()
        issue = Issue(message: "无法播放这段录音。请检查音频输出或重新录制。")
    }

    private func startMeter() {
        stopMeter()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self else { return }
                refreshMeter()
            }
        }
    }

    private func stopMeter() {
        meterTask?.cancel()
        meterTask = nil
    }

    private func refreshMeter() {
        if let recorder, recordingState == .recording {
            duration = completedDuration + recorder.currentTime
            recorder.updateMeters()
            level = max(0, min(1, (Double(recorder.averagePower(forChannel: 0)) + 60) / 60))
        }
        if let player, isPlaying {
            playbackProgress = player.duration > 0 ? min(1, player.currentTime / player.duration) : 0
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            isPlaying = false
            playbackProgress = flag ? 1 : 0
            stopMeter()
            deactivateSession()
            if !flag { failPlayback() }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.player, ObjectIdentifier(current) == identity else { return }
            failPlayback()
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Our own stop paths detach the delegate. Any other stop is unexpected;
        // a successfully closed file still must not be sent without the user.
        let identity = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, let current = self.recorder, ObjectIdentifier(current) == identity else { return }
            cancelDraft()
            issue = Issue(message: "录音已停止，未发送。请重新录制。")
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        audioRecorderDidFinishRecording(recorder, successfully: false)
    }

    private enum AudioFailure: Error { case recording, playback }

    /// Stream PCM buffers instead of loading an entire recording into memory.
    nonisolated static func joinSegments(_ inputs: [URL], to output: URL) throws -> TimeInterval {
        guard let firstURL = inputs.first else { throw CocoaError(.fileReadCorruptFile) }
        let first = try AVAudioFile(forReading: firstURL)
        let destination = try AVAudioFile(forWriting: output, settings: first.fileFormat.settings)
        var writtenFrames: AVAudioFramePosition = 0
        for url in inputs {
            let source = try AVAudioFile(forReading: url)
            guard source.processingFormat == destination.processingFormat,
                  let buffer = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4_096) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            while source.framePosition < source.length {
                try source.read(into: buffer)
                guard buffer.frameLength > 0 else { throw CocoaError(.fileReadCorruptFile) }
                try destination.write(from: buffer)
                writtenFrames += AVAudioFramePosition(buffer.frameLength)
            }
        }
        let duration = Double(writtenFrames) / destination.processingFormat.sampleRate
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        return duration
    }

    nonisolated private static func removeFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
