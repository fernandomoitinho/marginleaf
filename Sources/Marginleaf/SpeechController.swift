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
        restartCurrentBlock()
    }

    /// Picks a voice for a language (nil goes back to automatic) and, if reading, switches at once.
    func setVoice(identifier: String?, language: String) {
        var chosen = Settings.speechVoices
        chosen[language] = identifier
        Settings.speechVoices = chosen
        voiceCache.removeAll()
        restartCurrentBlock()
    }

    private func restartCurrentBlock() {
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
            let silent = segment.kind == .code || segment.kind == .diagram
            if !silent { previous = Self.language(of: segment.text, fallback: previous) }
            let text = silent ? Self.codeLabel(for: previous, diagram: segment.kind == .diagram) : segment.text
            result.append(Item(text: text, language: previous, pause: segment.kind == .heading ? 0.6 : 0.3))
        }
        return result
    }

    private static func codeLabel(for language: String, diagram: Bool) -> String {
        if diagram {
            switch language {
            case "pt": return "Diagrama."
            case "es": return "Diagrama."
            case "fr": return "Schéma."
            case "de": return "Diagramm."
            default: return "Diagram."
            }
        }
        switch language {
        case "pt": return "Bloco de código."
        case "es": return "Bloque de código."
        case "fr": return "Bloc de code."
        case "de": return "Codeblock."
        default: return "Code block."
        }
    }

    // MARK: Language and voice

    /// Voices worth offering: no robotic Eloquence voices, no novelty ones (Bells, Zarvox...).
    static func installedVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.identifier.contains("eloquence") && !$0.identifier.contains("speech.synthesis.voice")
        }
    }

    static func baseCode(_ tag: String) -> String {
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
        if let id = Settings.speechVoices[language], let chosen = AVSpeechSynthesisVoice(identifier: id) {
            voiceCache[language] = chosen
            return chosen
        }
        var preferred = Set(Locale.preferredLanguages.map { $0.replacingOccurrences(of: "_", with: "-") })
        preferred.insert("pt-PT")
        let candidates = Self.installedVoices().filter { Self.baseCode($0.language) == language }
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

/// View > Reading Voice: every installed voice, by language. Rebuilt each time it opens, so a voice
/// downloaded in System Settings shows up without restarting the app.
final class VoiceMenu: NSObject, NSMenuDelegate {
    static let shared = VoiceMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let voices = SpeechController.installedVoices()
        let chosen = Settings.speechVoices
        var groups: [String: [AVSpeechSynthesisVoice]] = [:]
        for voice in voices { groups[voice.language.replacingOccurrences(of: "_", with: "-"), default: []].append(voice) }

        var first = Locale.preferredLanguages.map { $0.replacingOccurrences(of: "_", with: "-") }
        first.insert("pt-PT", at: 0)
        let tags = groups.keys.sorted { a, b in
            let ia = first.firstIndex(of: a) ?? Int.max, ib = first.firstIndex(of: b) ?? Int.max
            return ia != ib ? ia < ib : a < b
        }

        for tag in tags {
            let code = SpeechController.baseCode(tag)
            let sub = NSMenu(title: tag)
            let auto = NSMenuItem(title: "Automatic (best installed)", action: #selector(pick(_:)), keyEquivalent: "")
            auto.target = self
            auto.representedObject = ["code": code] as NSDictionary
            auto.state = chosen[code] == nil ? .on : .off
            sub.addItem(auto)
            sub.addItem(.separator())
            let sorted = (groups[tag] ?? []).sorted {
                $0.quality.rawValue != $1.quality.rawValue ? $0.quality.rawValue > $1.quality.rawValue : $0.name < $1.name
            }
            for voice in sorted {
                let quality = voice.quality == .premium ? " (Premium)" : voice.quality == .enhanced ? " (Enhanced)" : ""
                let item = NSMenuItem(title: voice.name + quality, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["code": code, "id": voice.identifier] as NSDictionary
                item.state = chosen[code] == voice.identifier ? .on : .off
                sub.addItem(item)
            }
            let title = Locale.current.localizedString(forIdentifier: tag) ?? tag
            let group = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            group.submenu = sub
            menu.addItem(group)
        }
        if tags.isEmpty {
            let none = NSMenuItem(title: "No voices found", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        menu.addItem(.separator())
        let hint = NSMenuItem(title: "More voices: System Settings > Accessibility > Spoken Content", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? NSDictionary, let code = info["code"] as? String else { return }
        SpeechController.shared.setVoice(identifier: info["id"] as? String, language: code)
    }
}
