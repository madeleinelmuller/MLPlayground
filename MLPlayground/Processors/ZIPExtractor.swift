import Foundation
import zlib

// MARK: - Minimal ZIP Extractor (iOS-compatible, no external dependencies)
// Supports Stored (method 0) and raw DEFLATE (method 8) — the two formats
// used in Apple's .mlpackage.zip bundles.  Uses libz (always present on iOS).

enum ZIPExtractorError: Error {
    case readError
    case decompressionFailed
    case unsupportedMethod(UInt16)
    case noModelFound
}

struct ZIPExtractor {

    /// Extracts all entries in `zipURL` into `destDir`.
    /// Returns the URL of the first `.mlpackage` or `.mlmodel` found.
    @discardableResult
    static func extractModel(from zipURL: URL, into destDir: URL) throws -> URL {
        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        var pos = 0
        while pos + 30 <= data.count {
            // Local file header magic: PK 0x03 0x04
            guard data.u32le(at: pos) == 0x04034B50 else { pos += 1; continue }

            let method        = data.u16le(at: pos + 8)
            let compressedSz  = Int(data.u32le(at: pos + 18))
            let uncompressedSz = Int(data.u32le(at: pos + 22))
            let nameLen       = Int(data.u16le(at: pos + 26))
            let extraLen      = Int(data.u16le(at: pos + 28))

            let nameStart  = pos + 30
            let payloadStart = nameStart + nameLen + extraLen
            let payloadEnd   = payloadStart + compressedSz

            guard payloadEnd <= data.count, nameStart + nameLen <= data.count else { break }

            let entryName = String(data: data[nameStart ..< nameStart + nameLen], encoding: .utf8) ?? ""

            if !entryName.hasSuffix("/") && !entryName.isEmpty {
                let dest = destDir.appendingPathComponent(entryName)
                try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                let payload = Data(data[payloadStart ..< payloadEnd])

                switch method {
                case 0:   // Stored — no compression
                    try payload.write(to: dest)
                case 8:   // Deflate — raw DEFLATE via libz
                    guard let out = inflateRaw(payload, expectedSize: uncompressedSz) else {
                        throw ZIPExtractorError.decompressionFailed
                    }
                    try out.write(to: dest)
                default:
                    throw ZIPExtractorError.unsupportedMethod(method)
                }
            }

            pos = payloadEnd
        }

        // Return the first .mlpackage or .mlmodel in destDir
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: destDir, includingPropertiesForKeys: nil)) ?? []

        if let pkg = contents.first(where: { $0.pathExtension == "mlpackage" }) { return pkg }
        if let mlm = contents.first(where: { $0.pathExtension == "mlmodel"   }) { return mlm }
        throw ZIPExtractorError.noModelFound
    }

    // MARK: - Raw DEFLATE via libz

    /// Decompresses raw DEFLATE data (ZIP method 8).
    /// Uses inflateInit2 with a negative window-size to skip the zlib header.
    private static func inflateRaw(_ input: Data, expectedSize: Int) -> Data? {
        guard !input.isEmpty else { return Data() }

        var stream = z_stream()
        // Negative wbits = raw deflate (no zlib or gzip wrapper)
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION,
                            Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        let outSize = expectedSize > 0 ? expectedSize : max(input.count * 6, 4096)
        var output = Data(count: outSize)
        var written = 0

        let rc: Int32 = input.withUnsafeBytes { inBuf in
            output.withUnsafeMutableBytes { outBuf in
                stream.next_in   = UnsafeMutablePointer(
                    mutating: inBuf.bindMemory(to: Bytef.self).baseAddress!)
                stream.avail_in  = uInt(input.count)
                stream.next_out  = outBuf.bindMemory(to: Bytef.self).baseAddress!
                stream.avail_out = uInt(outSize)
                let rc = inflate(&stream, Z_FINISH)
                written = Int(stream.total_out)
                return rc
            }
        }

        guard (rc == Z_STREAM_END || rc == Z_OK), written > 0 else { return nil }
        return output.prefix(written)
    }
}

// MARK: - Data little-endian helpers

private extension Data {
    func u16le(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }
    func u32le(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }
}
