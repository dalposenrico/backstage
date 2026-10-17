import Foundation
import AVFoundation

/// Auditions MIDI clips in-app using macOS native CoreAudio General MIDI sound bank with zero latency.
@MainActor
public final class MidiClipPlayer: ObservableObject {
    public static let shared = MidiClipPlayer()

    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentClipId: String?

    private var midiPlayer: AVMIDIPlayer?

    public init() {}

    public func play(clip: AbletonClip, tempo: Double = 120.0) {
        stop()

        guard !clip.notes.isEmpty else { return }
        let data = StandardMidiWriter.generateMidiData(
            notes: clip.notes,
            tempo: tempo,
            trackName: clip.name
        )

        do {
            midiPlayer = try AVMIDIPlayer(data: data, soundBankURL: nil)
            midiPlayer?.prepareToPlay()
            midiPlayer?.play { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isPlaying = false
                    self?.currentClipId = nil
                }
            }
            isPlaying = true
            currentClipId = clip.id
        } catch {
            print("Failed to start MIDI playback: \(error.localizedDescription)")
            stop()
        }
    }

    public func stop() {
        if let player = midiPlayer, player.isPlaying {
            player.stop()
        }
        midiPlayer = nil
        isPlaying = false
        currentClipId = nil
    }

    public func toggle(clip: AbletonClip, tempo: Double = 120.0) {
        if isPlaying && currentClipId == clip.id {
            stop()
        } else {
            play(clip: clip, tempo: tempo)
        }
    }
}
