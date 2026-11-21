import AVFoundation

/// Plays the game's audio: the VM thread keeps a ring buffer of S16 stereo
/// frames filled (host.c), this drains it from the engine's render thread.
final class AudioOutput {
    private var engine: AVAudioEngine?
    private var rate = 0
    private let scratch = UnsafeMutablePointer<Int16>.allocate(capacity: 16384 * 2)

    /// Call regularly (the display link does): starts, restarts or stops the
    /// engine to follow what the game has open.
    func update() {
        var r: Int32 = 0
        let active = host_audio_active(&r) != 0
        if active && (engine == nil || Int(r) != rate) {
            start(rate: Int(r))
        } else if !active && engine != nil && host_running() == 0 {
            stop()
        }
    }

    private func start(rate: Int) {
        stop()
        guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: Double(rate), channels: 2) else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)

        let eng = AVAudioEngine()
        let scratch = self.scratch
        let node = AVAudioSourceNode(format: format) { _, _, frames, abl -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(abl)
            guard list.count >= 2,
                  let left = list[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = list[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            var done = 0
            let total = Int(frames)
            while done < total {
                let n = min(total - done, 16384)
                _ = host_audio_read(scratch, Int32(n))
                for i in 0..<n {
                    left[done + i] = Float(scratch[i * 2]) / 32768
                    right[done + i] = Float(scratch[i * 2 + 1]) / 32768
                }
                done += n
            }
            return noErr
        }
        eng.attach(node)
        eng.connect(node, to: eng.mainMixerNode, format: format)
        do { try eng.start() } catch { return }
        engine = eng
        self.rate = rate
        print("audio: engine started at \(rate) Hz")
    }

    func stop() {
        engine?.stop()
        engine = nil
        rate = 0
    }

    deinit { scratch.deallocate() }
}
