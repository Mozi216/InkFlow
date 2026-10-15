import Foundation
import NativeFingerprint
import OSLog

struct SongMatch {
    let song: NetEaseSong
    // The service reports the beginning of the audio window, not the response time.
    let position: Double
    let uptime: Double
    var title: String { song.title }
    var artist: String { song.artist }
}

private enum AudioMatchError: LocalizedError {
    case runtime(String), service(Int), response
    var errorDescription: String? {
        switch self {
        case .runtime(let reason): return "本机音频指纹计算失败：" + reason
        case .service(let code): return "网易云识曲暂不可用（\(code)）"
        case .response: return "网易云识曲响应无效"
        }
    }
}

// The bundled algorithm runs offline. Only its fingerprint goes to NetEase.
final class NetEaseFingerprint {
    private let queue = DispatchQueue(label: "InkFlow.fingerprint", qos: .userInitiated)

    func calculate(_ pcm: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let fingerprint = try autoreleasepool { try self.calculateOnQueue(pcm) }
                    continuation.resume(returning: fingerprint)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func calculateOnQueue(_ pcm: Data) throws -> String {
        guard pcm.count % MemoryLayout<Float>.size == 0 else { throw AudioMatchError.runtime("音频格式无效") }
        var bytes = [UInt8](repeating: 0, count: 65_536)
        var length = 0
        let code = pcm.withUnsafeBytes { input in
            bytes.withUnsafeMutableBufferPointer { output in
                inkflow_fingerprint(input.bindMemory(to: Float.self).baseAddress,
                    input.count / MemoryLayout<Float>.size, output.baseAddress, output.count, &length)
            }
        }
        if code == 1 { return "" }
        guard code == 0, length > 0, length <= bytes.count else {
            throw AudioMatchError.runtime("错误码 \(code)")
        }
        return Data(bytes.prefix(length)).base64EncodedString()
    }
}

actor NetEaseAudioMatcher {
    private let fingerprint = NetEaseFingerprint()
    private let session: URLSession
    private let logger = Logger(subsystem: "com.inkflow.mobile", category: "AudioMatch")
    private let sessionID = UUID().uuidString
    private var preferredID: Int64?

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 12
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    func match(pcm: Data, startUptime: Double) async throws -> SongMatch? {
        let began = ProcessInfo.processInfo.systemUptime
        let raw = try await fingerprint.calculate(pcm)
        try Task.checkCancellation()
        if raw.isEmpty { return nil }
        let calculated = ProcessInfo.processInfo.systemUptime
        var body = URLComponents()
        let duration = pcm.count / (8_000 * MemoryLayout<Float>.size)
        body.queryItems = ["sessionId": sessionID, "algorithmCode": "shazam_v2", "duration": String(duration),
                           "rawdata": raw, "times": "1", "decrypt": "1"].sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: URL(string: "https://interface.music.163.com/api/music/audio/match")!)
        request.httpMethod = "POST"
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("InkFlow/0.1", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw AudioMatchError.service((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_000_000 else { throw AudioMatchError.response }
            data.append(byte)
        }
        try Task.checkCancellation()
        let decoded = try JSONDecoder().decode(MatchResponse.self, from: data)
        guard decoded.code == 200 else { throw AudioMatchError.service(decoded.code) }
        let candidates = (decoded.data?.result ?? []).filter {
            $0.startTime >= 0 && $0.startTime.isFinite && $0.song.duration > $0.startTime
        }
        guard let found = candidates.first(where: { $0.song.id == preferredID }) ?? candidates.first else {
            logger.info("No match; fingerprint \(calculated - began) s; reason \(decoded.data?.noMatchReason ?? -1)")
            return nil
        }
        preferredID = found.song.id
        let song = NetEaseSong(id: found.song.id, title: found.song.name,
            artist: found.song.artists.map(\.name).joined(separator: " / "), duration: found.song.duration / 1000,
            artworkURL: (found.song.album?.picUrl).flatMap(URL.init(string:)))
        logger.info("Matched \(song.title, privacy: .public) / \(song.artist, privacy: .public); id \(song.id); offset \(found.startTime / 1000); fingerprint \(calculated - began) s; request \(ProcessInfo.processInfo.systemUptime - calculated) s")
        return SongMatch(song: song, position: found.startTime / 1000, uptime: startUptime)
    }

    private struct MatchResponse: Decodable {
        let code: Int
        let data: Results?
        struct Results: Decodable {
            let result: [Candidate]?
            let noMatchReason: Int?
        }
        struct Candidate: Decodable {
            let startTime: Double
            let song: Song
        }
        struct Song: Decodable {
            let id: Int64
            let name: String
            let artists: [Artist]
            let duration: Double
            let album: Album?
        }
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let picUrl: String? }
    }
}
