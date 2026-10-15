import Foundation
import Security

struct RelayConfiguration: Codable {
    var server: URL
    var accessKey: String

    func validate() throws {
        guard server.scheme == "https", server.host != nil, server.user == nil,
              server.password == nil, server.query == nil, server.fragment == nil,
              accessKey.count >= 32 else {
            throw RelayError.unavailable("配置需要 HTTPS 服务地址和有效的连接密钥。")
        }
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "InkFlowRelay", kSecAttrAccount as String: "configuration"]
    }

    static func load() -> Self? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        try validate()
        let data = try JSONEncoder().encode(self)
        let updated = SecItemUpdate(Self.query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw RelayError.unavailable("无法保存连接配置。") }
        var request = Self.query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else {
            throw RelayError.unavailable("无法保存连接配置。")
        }
    }
}
