import AVFoundation

/// 极简芯片电音：用 AVAudioSourceNode 实时合成方波/锯齿波音符序列。
final class Chiptune {
    static let shared = Chiptune()

    enum Cue { case done, alert, question, select, deny }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let sampleRate: Double = 44100
    private var queueLock = NSLock()
    private var notes: [(freq: Double, start: Double, dur: Double, type: Wave, vol: Double)] = []
    private var clock: Double = 0
    private var started = false

    enum Wave { case square, saw, triangle }

    private init() {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        source = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            self.queueLock.lock()
            let local = self.notes
            let base = self.clock
            self.queueLock.unlock()
            let ptr = abl[0].mData!.assumingMemoryBound(to: Float.self)
            for i in 0..<Int(frameCount) {
                let t = base + Double(i) / self.sampleRate
                var sample: Double = 0
                for n in local where t >= n.start && t < n.start + n.dur {
                    let local_t = t - n.start
                    let env = exp(-local_t * 6) * min(1, local_t * 60)  // 快起 + 指数衰减
                    let phase = (n.freq * local_t).truncatingRemainder(dividingBy: 1)
                    var w: Double
                    switch n.type {
                    case .square:   w = phase < 0.5 ? 1 : -1
                    case .saw:      w = 2 * phase - 1
                    case .triangle: w = phase < 0.5 ? (4*phase-1) : (3-4*phase)
                    }
                    sample += w * n.vol * env
                }
                ptr[i] = Float(max(-1, min(1, sample)))
            }
            self.queueLock.lock(); self.clock = base + Double(frameCount) / self.sampleRate; self.queueLock.unlock()
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: fmt)
    }

    private func ensureRunning() {
        guard !started else { return }
        do { try engine.start(); started = true } catch { }
    }

    func play(_ cue: Cue, enabled: Bool = true) {
        guard enabled else { return }
        ensureRunning()
        queueLock.lock(); let now = clock; queueLock.unlock()
        let seq: [(Double, Double, Double, Wave, Double)]
        let A4 = 440.0, C5 = 523.25, E5 = 659.25, G5 = 783.99, A5 = 880.0, C6 = 1046.5
        switch cue {
        case .done:     seq = [(G5,0,0.12,.square,0.18),(C6,0.09,0.16,.square,0.18),(E5,0,0.12,.triangle,0.10)]
        case .alert:    seq = [(A4,0,0.10,.saw,0.16),(A4*0.94,0.11,0.16,.saw,0.16)]
        case .question: seq = [(E5,0,0.07,.square,0.16),(A5,0.08,0.13,.square,0.16)]
        case .select:   seq = [(C5,0,0.04,.square,0.13),(G5,0.04,0.07,.square,0.13)]
        case .deny:     seq = [(A4*0.7,0,0.16,.saw,0.16)]
        }
        queueLock.lock()
        for s in seq { notes.append((s.0, now + s.1, s.2, s.3, s.4)) }
        // 清理已结束音符
        let cutoff = now
        notes.removeAll { $0.start + $0.dur < cutoff - 1 }
        queueLock.unlock()
    }
}
