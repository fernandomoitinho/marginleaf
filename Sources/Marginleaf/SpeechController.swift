import AppKit
import AVFoundation
import MediaPlayer
import NaturalLanguage
import MarginleafCore

/// Reads a note aloud with the system's own speech synthesiser: no model to ship, works offline.
/// Voices improve a lot once an Enhanced or Premium voice is installed
/// (System Settings > Accessibility > Spoken Content > System Voice > Manage Voices).
///
/// One reader for the whole app: starting a new reading replaces the current one.
final class SpeechController: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechController()
    static let stateChanged = Notification.Name("marginleafSpeechChanged")

    enum State { case idle, speaking, paused }

    private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            updateSystemControls()
            NotificationCenter.default.post(name: Self.stateChanged, object: self)
        }
    }

    private struct Item {
        let text: String
        let language: String
        let pause: TimeInterval
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var items: [Item] = []
    private var title = ""
    /// Utterances in flight. Anything not in here belongs to a reading we already replaced.
    private var live: [ObjectIdentifier: (utterance: AVSpeechUtterance, index: Int)] = [:]
    private var currentIndex = 0
    private var voiceCache: [String: AVSpeechSynthesisVoice] = [:]
    private var remoteConfigured = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Controls

    /// Idle: start. Speaking: pause. Paused: carry on.
    func toggle(markdown: String, title: String) {
        switch state {
        case .idle: start(markdown: markdown, title: title)
        case .speaking: pause()
        case .paused: resume()
        }
    }

    func start(markdown: String, title: String) {
        let segments = SpeechPlan.segments(from: markdown)
        guard !segments.isEmpty else { return }
        self.title = title
        items = makeItems(from: segments)
        speak(from: 0)
    }

    func pause() {
        guard state == .speaking else { return }
        if synthesizer.pauseSpeaking(at: .immediate) { state = .paused }
    }

    func resume() {
        guard state == .paused else { return }
        if synthesizer.continueSpeaking() { state = .speaking }
    }

    func stop() {
        halt()
        items = []
        state = .idle
    }

    /// Takes effect straight away: the current block restarts at the new speed.
    func setSpeed(_ speed: Double) {
        Settings.speechSpeed = speed
        guard state != .idle else { return }
        let wasPaused = state == .paused
        speak(from: currentIndex)
        if wasPaused { pause() }
    }

    // MARK: Speaking

    private func halt() {
        live.removeAll()
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func speak(from start: Int) {
        halt()
        let rate = min(AVSpeechUtteranceMaximumSpeechRate,
                       max(AVSpeechUtteranceMinimumSpeechRate,
                           AVSpeechUtteranceDefaultSpeechRate * Float(Settings.speechSpeed)))
        for index in items.indices where index >= start {
            let item = items[index]
            let utterance = AVSpeechUtterance(string: item.text)
            utterance.voice = voice(for: item.language)
            utterance.rate = rate
            utterance.postUtteranceDelay = item.pause
            live[ObjectIdentifier(utterance)] = (utterance, index)
            synthesizer.speak(utterance)
        }
        currentIndex = start
        state = .speaking
    }

    private func makeItems(from segments: [SpeechSegment]) -> [Item] {
        var result: [Item] = []
        var previous = Locale.preferredLanguages.first.map(Self.baseCode) ?? "en"
        for segment in segments {
            if segment.kind != .code { previous = Self.language(of: segment.text, fallback: previous) }
            let text = segment.kind == .code ? Self.codeLabel(for: previous) : segment.text
            result.append(Item(text: text, language: previous, pause: segment.kind == .heading ? 0.6 : 0.3))
        }
        return result
    }

    private static func codeLabel(for language: String) -> String {
        switch language {
        case "pt": return "Bloco de código."
        case "es": return "Bloque de código."
        case "fr": return "Bloc de code."
        case "de": return "Codeblock."
        default: return "Code block."
        }
    }

    // MARK: Language and voice

    private static func baseCode(_ tag: String) -> String {
        String(tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "en").lowercased()
    }

    /// Notes mix languages, so each block is detected on its own. Short or unclear text keeps
    /// the language of the block before it.
    private static func language(of text: String, fallback: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let best = recognizer.languageHypotheses(withMaximum: 1).first, best.value > 0.6 {
            return baseCode(best.key.rawValue)
        }
        return fallback
    }

    /// The best installed voice for a language: Premium over Enhanced over standard, and the
    /// regions the user asked the system for first (European Portuguese counts as asked for).
    private func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if let cached = voiceCache[language] { return cached }
        var preferred = Set(Locale.preferredLanguages.map { $0.replacingOccurrences(of: "_", with: "-") })
        preferred.insert("pt-PT")
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            Self.baseCode(voice.language) == language
                && !voice.identifier.contains("eloquence")
                && !voice.identifier.contains("speech.synthesis.voice")
        }
        func score(_ voice: AVSpeechSynthesisVoice) -> Int {
            voice.quality.rawValue * 100 + (preferred.contains(voice.language) ? 10 : 0)
        }
        let best = candidates.max { score($0) < score($1) }
            ?? AVSpeechSynthesisVoice(language: language)
        if let best { voiceCache[language] = best }
        return best
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        if let entry = live[ObjectIdentifier(utterance)] { currentIndex = entry.index }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard live.removeValue(forKey: ObjectIdentifier(utterance)) != nil else { return }
        if live.isEmpty { state = .idle }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        guard live.removeValue(forKey: ObjectIdentifier(utterance)) != nil else { return }
        if live.isEmpty { state = .idle }
    }

    // MARK: Media keys and Now Playing

    private func configureRemoteCommands() {
        guard !remoteConfigured else { return }
        remoteConfigured = true
        let center = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, _ action: @escaping (SpeechController) -> Void) {
            _ = command.addTarget { [weak self] _ in
                DispatchQueue.main.async { if let self { action(self) } }
                return .success
            }
        }
        bind(center.playCommand) { $0.resume() }
        bind(center.pauseCommand) { $0.pause() }
        bind(center.stopCommand) { $0.stop() }
        bind(center.togglePlayPauseCommand) { speech in
            if speech.state == .paused { speech.resume() } else { speech.pause() }
        }
    }

    private func updateSystemControls() {
        configureRemoteCommands()
        let center = MPRemoteCommandCenter.shared()
        let active = state != .idle
        for command in [center.playCommand, center.pauseCommand, center.stopCommand, center.togglePlayPauseCommand] {
            command.isEnabled = active
        }
        let info = MPNowPlayingInfoCenter.default()
        switch state {
        case .idle:
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
        case .speaking:
            info.nowPlayingInfo = [MPMediaItemPropertyTitle: title, MPMediaItemPropertyArtist: "Marginleaf"]
            info.playbackState = .playing
        case .paused:
            info.playbackState = .paused
        }
    }
}
