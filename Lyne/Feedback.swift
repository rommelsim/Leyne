// Lyne — sensory feedback system. Ported from feedback.js.
// Three modalities: audio (synthesised tones), haptic (Core Haptics / UIKit
// generators), motion (a published event the device shell subscribes to for a
// shake). Four intensities: tap / select / success / arrival.
//
// The app stays quiet by default — only select/success/arrival fire ambiently.

import SwiftUI
import AVFoundation
import UIKit

enum FeedbackKind { case tap, select, success, arrival }

final class Feedback: ObservableObject {
    static let shared = Feedback()

    @Published var sound = true
    @Published var haptic = true
    @Published var motion = false

    /// Emitted on success/arrival so the device shell can shake.
    @Published var shake: (kind: FeedbackKind, id: UUID)? = nil

    private var engine: AVAudioEngine?
    private var mixer: AVAudioMixerNode?

    func config(sound: Bool, haptic: Bool, motion: Bool) {
        self.sound = sound; self.haptic = haptic; self.motion = motion
    }

    // ─── Public intensities ───────────────────────────────────
    func tap() {
        blip(freq: 1500, gain: 0.03, decay: 0.04, type: .sine)
        vibrate(.light)
    }

    func select() {
        blip(freq: 900, gain: 0.05, decay: 0.07, type: .triangle)
        blip(freq: 1350, gain: 0.025, decay: 0.06, type: .sine, delay: 0.02)
        vibrate(.soft)
    }

    func success() {
        blip(freq: 660, gain: 0.05, decay: 0.09, type: .sine)
        blip(freq: 990, gain: 0.06, decay: 0.13, type: .sine, delay: 0.08)
        notify(.success)
        emitShake(.success)
    }

    func arrival() {
        blip(freq: 740,  gain: 0.06,  decay: 0.16, type: .sine)
        blip(freq: 880,  gain: 0.06,  decay: 0.16, type: .sine, delay: 0.11)
        blip(freq: 1108, gain: 0.055, decay: 0.22, type: .sine, delay: 0.22)
        notify(.warning)
        emitShake(.arrival)
    }

    // ─── Motion ───────────────────────────────────────────────
    private func emitShake(_ kind: FeedbackKind) {
        guard motion else { return }
        shake = (kind, UUID())
    }

    // ─── Haptics ──────────────────────────────────────────────
    private func vibrate(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        guard haptic else { return }
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare(); g.impactOccurred()
    }
    private func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard haptic else { return }
        let g = UINotificationFeedbackGenerator()
        g.prepare(); g.notificationOccurred(type)
    }

    // ─── Audio (short synthesised tone, like feedback.js blip) ─
    enum Wave { case sine, triangle }

    private func ensureEngine() -> (AVAudioEngine, AVAudioMixerNode)? {
        if let e = engine, let m = mixer { return (e, m) }
        let e = AVAudioEngine()
        let m = e.mainMixerNode
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try e.start()
        } catch { return nil }
        engine = e; mixer = m
        return (e, m)
    }

    private func blip(freq: Double, gain: Double, decay: Double,
                      type: Wave, delay: Double = 0) {
        guard sound else { return }
        guard let (engine, mixer) = ensureEngine() else { return }
        let sampleRate = mixer.outputFormat(forBus: 0).sampleRate > 0
            ? mixer.outputFormat(forBus: 0).sampleRate : 44100
        let attack = 0.004
        let total = attack + decay + 0.02
        let frames = AVAudioFrameCount(sampleRate * total)
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return }
        buffer.frameLength = frames
        guard let ch = buffer.floatChannelData?[0] else { return }

        for i in 0..<Int(frames) {
            let tt = Double(i) / sampleRate
            // simple ADSR-ish envelope mirroring the web gain ramp
            let env: Double
            if tt < attack {
                env = (tt / attack) * gain
            } else {
                let d = tt - attack
                env = gain * exp(-d / (decay / 4.0))
            }
            let phase = 2.0 * Double.pi * freq * tt
            let s: Double
            switch type {
            case .sine: s = sin(phase)
            case .triangle: s = (2.0 / Double.pi) * asin(sin(phase))
            }
            ch[i] = Float(s * env)
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: mixer, format: format)
        let when = delay > 0
            ? AVAudioTime(hostTime: mach_absolute_time())
            : nil
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak engine] in
            DispatchQueue.main.async {
                player.stop()
                engine?.detach(player)
            }
        }
        _ = when
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            player.play()
        }
    }
}
