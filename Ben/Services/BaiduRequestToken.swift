import CommonCrypto
import CryptoKit
import Foundation

/// Native implementation of the web client's P2 request format.
/// Protocol constants are public SDK values, not account credentials.
enum BaiduRequestToken {
    private static let sdkTimestamp = "1794729605391"
    private static let seed = "mayiygakawqakuay"
    private static let iv = "1234567887654321"
    private static let keySuffix = "b71c2fa3ed82f"
    private static let fieldSuffix = "a31c7afce4fa5"
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36"

    static func make(baiduid: String, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws -> String {
        let nonce = String(UInt64.random(in: 0..<UInt64.max), radix: 32) + String(now, radix: 32)
        let fields: [String] = [nonce, "", "300_7ex98", "false", "0", "", "1", userAgent, String(now), "MacIntel", fieldSuffix]
        let check = Int(sha1(fields.joined(separator: "_")).prefix(4), radix: 16)!
        let payload: [String: Any] = [
            "d0": nonce, "ua": userAgent, "baiduid": baiduid, "platform": "MacIntel",
            "d23": 2, "hf": "", "h0": false, "h1": 0, "hfe": "300_7ex98",
            "d1": "", "d2": 1, "d4": 1, "d5": 0, "d432": 0, "d437": 0,
            "d11": 0, "d12": "71,6160", "d13": "298,232,297,320", "d8": 0,
            "d78": check, "d420": 0, "clientTs": now, "extra": "", "d7": 0,
            "d9": "", "odkp": 0, "version": "2.5.2.1"
        ]
        return try encode(payload: payload, clientTimestamp: now)
    }

    static func encode(payload: [String: Any], clientTimestamp: Int64) throws -> String {
        let json = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys, .withoutEscapingSlashes])
        let keyMaterial = sha1(sdkTimestamp + String(clientTimestamp) + keySuffix)
        let bytes = transform(Array(json), using: keyMaterial)
        let key = transform(Array(seed.utf8), using: keyMaterial)
        guard key.count == kCCKeySizeAES128 else { throw TranslationServiceError.invalidResponse }
        var encrypted = [UInt8](repeating: 0, count: bytes.count + kCCBlockSizeAES128)
        var written = 0
        let status = encrypted.withUnsafeMutableBytes { output in
            bytes.withUnsafeBytes { input in
                key.withUnsafeBytes { keyBuffer in
                    Array(iv.utf8).withUnsafeBytes { ivBuffer in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                keyBuffer.baseAddress, key.count, ivBuffer.baseAddress,
                                input.baseAddress, bytes.count, output.baseAddress, output.count, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw TranslationServiceError.invalidResponse }
        return "P2_" + sdkTimestamp + "_" + String(clientTimestamp) + "_" + Data(encrypted.prefix(written)).base64EncodedString()
    }

    private static func sha1(_ value: String) -> String {
        Insecure.SHA1.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func transform(_ bytes: [UInt8], using hash: String) -> [UInt8] {
        guard !bytes.isEmpty else { return [] }
        var output = bytes
        let key = Array(hash.utf8)
        let stride = max(1, (bytes.count + 59) / 60)
        var offset = 0
        for index in Swift.stride(from: 0, to: bytes.count, by: stride) {
            let mixed = Int(bytes[index] ^ key[offset % key.count])
            let value = index & 1 == 1 ? ((~mixed & 255) ^ 85) : ((7 * mixed) & 255)
            output[index] = UInt8(((value << 3) | (value >> 5)) & 255)
            offset += 1
        }
        return output
    }
}
