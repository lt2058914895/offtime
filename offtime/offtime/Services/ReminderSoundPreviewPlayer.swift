import AVFoundation
import Combine
import Foundation

@MainActor
final class ReminderSoundPreviewPlayer: ObservableObject {
    @Published private(set) var playingSound: ReminderSound?

    private var player: AVAudioPlayer?
    private var stopTask: Task<Void, Never>?
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func toggle(_ sound: ReminderSound) {
        if playingSound == sound {
            stop()
        } else {
            play(sound)
        }
    }

    func play(_ sound: ReminderSound) {
        guard let url = sound.resourceURL(in: bundle) else { return }

        stop(keepsSessionActive: true)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.85
            player.prepareToPlay()
            guard player.play() else { return }
            self.player = player
            playingSound = sound

            let duration = max(player.duration, 0.1)
            stopTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        } catch {
            self.player = nil
            playingSound = nil
        }
    }

    func stop() {
        stop(keepsSessionActive: false)
    }

    private func stop(keepsSessionActive: Bool) {
        stopTask?.cancel()
        stopTask = nil
        player?.stop()
        player = nil
        playingSound = nil

        guard !keepsSessionActive else { return }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}
