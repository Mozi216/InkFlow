import Foundation
import InkFlowCore
import ImageIO
import UniformTypeIdentifiers

struct NetEaseSong: Identifiable, Equatable {
    var id: Int64
    var title: String
    var artist: String
    var duration: Double
    var artworkURL: URL? = nil
}

enum LyricsServiceError: LocalizedError {
    case response, tooLarge, noCandidate
    var errorDescription: String? {
        switch self {
        case .response: return "网易云暂时没有返回歌词"
        case .tooLarge: return "歌词响应超过大小限制"
        case .noCandidate: return "未找到对应版本的歌曲"
        }
    }
}

actor NetEaseClient {
    private let session: URLSession
    private var cache: [Int64: LyricDocument] = [:]
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    private func request(_ path: String, _ query: [String: String]) async throws -> [String: Any] {
        var components = URLComponents(string: "https://music.163.com" + path)!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("InkFlow/0.1", forHTTPHeaderField: "User-Agent")
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LyricsServiceError.response }
        var data = Data()
        for try await byte in stream {
            guard data.count < 2_000_000 else { throw LyricsServiceError.tooLarge }
            data.append(byte)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["code"] as? Int == 200 else { throw LyricsServiceError.response }
        return json
    }

    func search(title: String, artist: String) async throws -> [NetEaseSong] {
        let data = try await request("/api/search/get/web", ["s": "\(title) \(artist)", "type": "1", "limit": "10"])
        let result = data["result"] as? [String: Any]
        return (result?["songs"] as? [[String: Any]] ?? []).compactMap { song in
            guard let id = song["id"] as? NSNumber, let title = song["name"] as? String else { return nil }
            let artists = (song["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: " / ")
            return NetEaseSong(id: id.int64Value, title: title, artist: artists,
                               duration: (song["duration"] as? Double ?? 0) / 1000,
                               artworkURL: ((song["album"] as? [String: Any])?["picUrl"] as? String).flatMap(URL.init(string:)))
        }
    }

    func artwork(for song: NetEaseSong) async -> Data? {
        do {
            var url = song.artworkURL
            if url == nil {
                let detail = try await request("/api/song/detail/", ["id": String(song.id), "ids": "[\(song.id)]"])
                let item = (detail["songs"] as? [[String: Any]])?.first
                url = ((item?["album"] as? [String: Any])?["picUrl"] as? String).flatMap(URL.init(string:))
            }
            guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let host = components.host, host.hasSuffix("music.126.net") || host.hasSuffix("music.163.com") else { return nil }
            components.scheme = "https"
            components.queryItems = [URLQueryItem(name: "param", value: "64y64")]
            guard let thumbnailURL = components.url else { return nil }
            let (bytes, response) = try await session.bytes(from: thumbnailURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 300_000 else { return nil }
                data.append(byte)
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) else { return nil }
            let result = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.28] as CFDictionary)
            guard CGImageDestinationFinalize(destination), result.length <= 1_200 else { return nil }
            return result as Data
        } catch { return nil }
    }

    func lyrics(for song: NetEaseSong) async throws -> LyricDocument {
        if let cached = cache[song.id] { return cached }
        let data = try await request("/api/song/lyric/v1", ["id": String(song.id), "cp": "false", "lv": "-1",
            "tv": "-1", "rv": "-1", "kv": "-1", "yv": "-1", "ytv": "-1", "yrv": "-1"])
        let yrc = (data["yrc"] as? [String: Any])?["lyric"] as? String
        let lrc = (data["lrc"] as? [String: Any])?["lyric"] as? String
        let document = LyricParser.parse(yrc: yrc, lrc: lrc, duration: song.duration)
        if cache.count >= 12 { cache.removeAll(keepingCapacity: true) }
        cache[song.id] = document
        return document
    }

    nonisolated static func bestMatch(_ songs: [NetEaseSong], title: String, artist: String) -> NetEaseSong? {
        func key(_ value: String) -> String {
            value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
        }
        let titleKey = key(title), artistKey = key(artist)
        let exact = songs.filter { key($0.title) == titleKey && !artistKey.isEmpty && key($0.artist).contains(artistKey) }
        // 不拿搜索第一项冒充原曲；翻唱、现场版交给使用者明确选择。
        return exact.count == 1 ? exact[0] : nil
    }
}
