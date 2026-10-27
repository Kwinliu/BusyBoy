import AVFoundation
import Foundation

/// Local PCM synthesis: a stepper motor, roller clicks and paper friction.
/// No network, microphone or bundled recording is needed.
@MainActor
final class PrinterAudio {
    private var player: AVAudioPlayer?

    func printPaper(duration: Double) {
        play(duration: duration, volume: 0.38, tearing: false)
    }

    func tearPaper() { play(duration: 0.42, volume: 0.48, tearing: true) }
    func stop() { player?.stop(); player = nil }

    private func play(duration: Double, volume: Float, tearing: Bool) {
        let rate = 44100
        let count = Int(duration * Double(rate))
        var pcm = Data(capacity: count * 2)
        var random: UInt32 = 0x51AC2D7B
        var previousNoise = 0.0
        var lowNoise = 0.0
        var phase = 0.0
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            random = random &* 1664525 &+ 1013904223
            let noise = Double(random) / Double(UInt32.max) * 2 - 1
            lowNoise += 0.19 * (noise - lowNoise)
            let highNoise = noise - previousNoise
            previousNoise = noise
            let envelope = min(1, time / 0.025) * min(1, (duration - time) / 0.045)
            let value: Double
            if tearing {
                let rip = pow(sin(.pi * min(1, time / duration)), 0.7)
                let tooth = 0.5 + 0.5 * sin(2 * .pi * 73 * time)
                value = envelope * rip * (0.29 * highNoise * tooth + 0.18 * lowNoise)
            } else {
                let batch = time.truncatingRemainder(dividingBy: 0.145)
                let contact = batch < 0.11 ? 1.0 : 0.24
                let speed = 175 + 24 * min(1, time / 0.12) + 3 * sin(2 * .pi * 8 * time)
                phase += 2 * .pi * speed / Double(rate)
                let motor = 0.32 * sin(phase) + 0.17 * sin(phase * 2) + 0.11 * sin(phase * 5)
                let clack = exp(-batch / 0.006) * sin(2 * .pi * 1300 * time) * 0.4
                let friction = lowNoise * 0.16 + highNoise * 0.055
                value = envelope * (contact * (motor + friction) + clack) * 0.42
            }
            var sample = Int16(max(-0.95, min(0.95, value)) * 32767).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        playWave(Self.wave(pcm: pcm, rate: rate), volume: volume)
    }

    func moveMechanism(opening: Bool, duration: Double) {
        playWave(Self.mechanismWave(opening: opening, duration: min(0.145, duration)), volume: 0.42)
    }

    func pressButton() { moveMechanism(opening: true, duration: 0.145) }

    func ringAlarm() { playWave(Self.alarmWave(), volume: 0.55, looping: true) }

    /// Three clean chimes, then a pause. Separate from the existing button sound.
    static func alarmWave() -> Data {
        let rate = 44100
        let count = Int(2.5 * Double(rate))
        var pcm = Data(capacity: count * 2)
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            var value = 0.0
            for onset in [0.0, 0.32, 0.64] {
                let age = time - onset
                if age >= 0 {
                    let envelope = min(1, age / 0.004) * exp(-age / 0.16)
                    value += envelope * (sin(2 * .pi * 988 * age) * 0.27 + sin(2 * .pi * 1482 * age) * 0.08)
                }
            }
            var sample = Int16(max(-0.95, min(0.95, value)) * 32767).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        return wave(pcm: pcm, rate: rate)
    }

    /// A short shutter-style snap, followed by a quieter spring return.
    static func mechanismWave(opening: Bool, duration: Double) -> Data {
        let rate = 44100
        let duration = max(0.08, duration)
        let count = Int(duration * Double(rate))
        var pcm = Data(capacity: count * 2)
        var random: UInt32 = opening ? 0xA17E345B : 0x345BC1AA
        var lowNoise = 0.0
        let pitch = opening ? 1.0 : 0.93
        let returnTime = opening ? 0.042 : 0.036
        for index in 0..<count {
            let time = Double(index) / Double(rate)
            random = random &* 1664525 &+ 1013904223
            let noise = Double(random) / Double(UInt32.max) * 2 - 1
            lowNoise += 0.22 * (noise - lowNoise)
            let highNoise = noise - lowNoise
            func impact(_ offset: Double, decay: Double) -> Double {
                let age = time - offset
                guard age >= 0 else { return 0 }
                return min(1, age / 0.00035) * exp(-age / decay)
            }
            let snap = impact(0.001, decay: 0.0045) * (highNoise * 0.5 + sin(2 * .pi * 1430 * pitch * time) * 0.15)
            let body = impact(0.002, decay: 0.015) * (sin(2 * .pi * 225 * time) * 0.17 + sin(2 * .pi * 470 * pitch * time) * 0.07)
            let returnAge = max(0, time - returnTime)
            let spring = impact(returnTime, decay: 0.0075) * (highNoise * 0.42 + sin(2 * .pi * 1960 * pitch * returnAge) * 0.12)
            let latch = impact(returnTime + 0.013, decay: 0.004) * highNoise * 0.12
            let settle = impact(returnTime + 0.002, decay: 0.014) * sin(2 * .pi * 175 * returnAge) * 0.12
            let curtainAge = (time - 0.007) / 0.025
            let curtain = curtainAge > 0 && curtainAge < 1 ? sin(.pi * curtainAge) * highNoise * 0.055 : 0
            let fade = min(1, max(0, (duration - time) / 0.012))
            let value = (snap + body + spring + latch + settle + curtain) * fade * 0.9
            var sample = Int16(max(-0.95, min(0.95, value)) * 32767).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        return wave(pcm: pcm, rate: rate)
    }

    private static func wave(pcm: Data, rate: Int) -> Data {
        var wave = Data()
        func append32(_ number: UInt32) {
            var value = number.littleEndian
            withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) }
        }
        func append16(_ number: UInt16) {
            var value = number.littleEndian
            withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) }
        }
        wave.append(Data("RIFF".utf8)); append32(UInt32(pcm.count + 36)); wave.append(Data("WAVEfmt ".utf8))
        append32(16); append16(1); append16(1); append32(UInt32(rate)); append32(UInt32(rate * 2)); append16(2); append16(16)
        wave.append(Data("data".utf8)); append32(UInt32(pcm.count)); wave.append(pcm)
        return wave
    }

    private func playWave(_ wave: Data, volume: Float, looping: Bool = false) {
        do {
            player = try AVAudioPlayer(data: wave, fileTypeHint: AVFileType.wav.rawValue)
            player?.volume = volume
            player?.numberOfLoops = looping ? -1 : 0
            player?.prepareToPlay()
            player?.play()
        } catch { NSLog("PaperTodo: mechanical audio unavailable: %@", error.localizedDescription) }
    }
}

@MainActor
enum ButtonFeedback {
    private static let audio = PrinterAudio()
    static func play() {
        guard UserDefaults.standard.object(forKey: "mechanicalSoundEnabled") as? Bool ?? true else { return }
        audio.pressButton()
    }
}
