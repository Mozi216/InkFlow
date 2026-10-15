import XCTest
import Foundation
import CryptoKit
import NativeFingerprint

final class NativeFingerprintTests: XCTestCase {
    private func extract(_ samples: [Float]) -> (Int32, String) {
        var output = [UInt8](repeating: 0, count: 65_536)
        var length = 0
        let result = samples.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { buffer in
                inkflow_fingerprint(input.baseAddress, input.count, buffer.baseAddress, buffer.count, &length)
            }
        }
        return (result, Data(output.prefix(length)).base64EncodedString())
    }

    func testMatchesWasmFingerprintAcrossRepeatedCalls() {
        var seed: UInt32 = 0x1234abcd
        let samples: [Float] = (0..<96_000).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Float(Int32(bitPattern: seed)) / 2_147_483_648 * 0.25
        }
        for _ in 0..<20 {
            let (result, fingerprint) = extract(samples)
            XCTAssertEqual(result, 0)
            let hash = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, "92175b608e6bc8b4c653516256f927df2fe1fe9fec0f09eed923393279e7a7d6")
        }
    }

    func testSilenceAndInvalidSamplesCannotEnterExtractor() {
        XCTAssertEqual(extract(Array(repeating: 0, count: 48_000)).0, 1)
        XCTAssertEqual(extract(Array(repeating: .nan, count: 48_000)).0, -1)
        XCTAssertEqual(extract(Array(repeating: 0.1, count: 100)).0, -1)
        XCTAssertEqual(extract(Array(repeating: 0.1, count: 96_001)).0, -1)
    }
}
