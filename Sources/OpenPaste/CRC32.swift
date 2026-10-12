import Foundation

/// CRC32（zlib 多项式 0xEDB88320）——Paste 同款去重/校验指纹算法。
/// 剪贴板去重只需"同内容判等"，CRC32 足够，无需加密级哈希。
enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for byte in raw {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFFFFFF
    }

    static func checksum(_ string: String) -> UInt32 {
        checksum(Data(string.utf8))
    }
}
