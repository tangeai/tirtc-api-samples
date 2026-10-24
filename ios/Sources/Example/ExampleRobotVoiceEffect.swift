import Foundation

final class ExampleRobotVoiceEffect {
    private let phaseStep: Double
    private var phase = 0.0

    init(sampleRate: Int) {
        phaseStep = 2.0 * Double.pi * 80.0 / Double(sampleRate)
    }

    func reset() { phase = 0.0 }

    func process(_ pcm: Data) -> Data {
        guard !pcm.isEmpty, pcm.count.isMultiple(of: 2) else { return Data() }
        var output = Data(count: pcm.count)
        pcm.withUnsafeBytes { sourceBytes in
            output.withUnsafeMutableBytes { destinationBytes in
                let source = sourceBytes.bindMemory(to: UInt8.self)
                let destination = destinationBytes.bindMemory(to: UInt8.self)
                for offset in stride(from: 0, to: pcm.count, by: 2) {
                    let bits = UInt16(source[offset]) | (UInt16(source[offset + 1]) << 8)
                    let sample = Int16(bitPattern: bits)
                    let modulated = (Double(sample) * sin(phase)).rounded()
                    let clamped = max(Double(Int16.min), min(Double(Int16.max), modulated))
                    let result = UInt16(bitPattern: Int16(clamped))
                    destination[offset] = UInt8(truncatingIfNeeded: result)
                    destination[offset + 1] = UInt8(truncatingIfNeeded: result >> 8)
                    phase += phaseStep
                    if phase >= 2.0 * Double.pi {
                        phase.formTruncatingRemainder(dividingBy: 2.0 * Double.pi)
                    }
                }
            }
        }
        return output
    }
}
