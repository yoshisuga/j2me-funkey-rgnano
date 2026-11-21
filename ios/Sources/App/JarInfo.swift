import Foundation
import Compression

/// Reads META-INF/MANIFEST.MF out of a jar (zip), enough to find the MIDlet class.
struct JarInfo {
    let manifest: String
    let name: String
    let mainClass: String

    init?(jarURL: URL) {
        guard let data = try? Data(contentsOf: jarURL, options: .mappedIfSafe),
              let mf = JarInfo.readEntry(data, named: "META-INF/MANIFEST.MF"),
              let text = String(data: mf, encoding: .utf8) ?? String(data: mf, encoding: .isoLatin1)
        else { return nil }
        // manifest lines continue on lines that start with a space
        let joined = text.replacingOccurrences(of: "\r\n ", with: "").replacingOccurrences(of: "\n ", with: "")
        var props: [String: String] = [:]
        for line in joined.components(separatedBy: CharacterSet(charactersIn: "\r\n")) {
            guard let i = line.firstIndex(of: ":") else { continue }
            props[String(line[..<i])] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        guard let m1 = props["MIDlet-1"] else { return nil }
        let parts = m1.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3, !parts[2].isEmpty else { return nil }
        manifest = joined
        name = props["MIDlet-Name"] ?? parts[0]
        mainClass = parts[2]
    }

    private static func le16(_ d: Data, _ o: Int) -> Int { Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
    private static func le32(_ d: Data, _ o: Int) -> Int { le16(d, o) | le16(d, o + 2) << 16 }

    static func readEntry(_ d: Data, named wanted: String) -> Data? {
        // end of central directory record
        var eocd = -1
        var i = d.count - 22
        while i >= max(0, d.count - 66000) {
            if le32(d, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { return nil }
        let count = le16(d, eocd + 10)
        var p = le32(d, eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= d.count, le32(d, p) == 0x02014b50 else { return nil }
            let method = le16(d, p + 10)
            let csize = le32(d, p + 20), usize = le32(d, p + 24)
            let nlen = le16(d, p + 28), xlen = le16(d, p + 30), clen = le16(d, p + 32)
            let local = le32(d, p + 42)
            let name = String(decoding: d[(d.startIndex + p + 46)..<(d.startIndex + p + 46 + nlen)], as: UTF8.self)
            if name.caseInsensitiveCompare(wanted) == .orderedSame {
                let lnlen = le16(d, local + 26), lxlen = le16(d, local + 28)
                let start = d.startIndex + local + 30 + lnlen + lxlen
                let raw = d[start..<(start + csize)]
                if method == 0 { return Data(raw) }
                guard method == 8 else { return nil }
                var out = Data(count: usize)
                let n = out.withUnsafeMutableBytes { dst in
                    raw.withUnsafeBytes { src in
                        compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, usize,
                                                  src.bindMemory(to: UInt8.self).baseAddress!, csize,
                                                  nil, COMPRESSION_ZLIB)
                    }
                }
                return n == usize ? out : nil
            }
            p += 46 + nlen + xlen + clen
        }
        return nil
    }
}
