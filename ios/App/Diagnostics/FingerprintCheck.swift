import CryptoKit
import Foundation

enum FingerprintCheck {
    static func run() async -> [String: String] {
        var seed: UInt32 = 0x1234abcd
        let samples: [Float] = (0..<96_000).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed)) / 2_147_483_648 * 0.25
        }
        let pcm = samples.withUnsafeBytes { Data($0) }
        let engine = NetEaseFingerprint()
        let expected = "92175b608e6bc8b4c653516256f927df2fe1fe9fec0f09eed923393279e7a7d6"
        var timings: [String] = []
        do {
            for _ in 0..<3 {
                let began = ProcessInfo.processInfo.systemUptime
                let value = try await engine.calculate(pcm)
                let hash = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
                guard hash == expected else { return ["result": "failed", "reason": "fingerprint mismatch", "hash": hash] }
                timings.append(String(format: "%.3f", ProcessInfo.processInfo.systemUptime - began))
            }
            return ["result": "passed", "seconds": timings.joined(separator: ","), "input": "generated noise, no recording"]
        } catch { return ["result": "failed", "reason": error.localizedDescription] }
    }
}
