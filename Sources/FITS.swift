import Foundation

struct FITSError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct FITSHDU {
    let index: Int
    let cards: [String]
    let values: [String: String]
    let offset: Int
    let dimensions: [Int]
    let bitpix: Int
    var name: String { values["EXTNAME"] ?? (index == 0 ? "PRIMARY" : "HDU \(index)") }
    var isImage: Bool {
        dimensions.count == 2 && dimensions.allSatisfy { $0 > 1 } &&
        (index == 0 || values["XTENSION"] == "IMAGE")
    }
    func number(_ key: String, _ fallback: Double) -> Double {
        Double((values[key] ?? "").replacingOccurrences(of: "D", with: "E")) ?? fallback
    }
}

struct Potential {
    let width: Int
    let height: Int
    let values: [Double]
    let lx: Double
    let ly: Double
    let fieldCoordinates: Bool
    let colorLimit: Double
    let minimum: Double
    let maximum: Double
    let finiteCount: Int
    let hduIndex: Int
}

final class FITSDocument {
    let url: URL
    let data: Data
    let hdus: [FITSHDU]

    static func value(_ card: String) -> String? {
        let bytes = Array(card.utf8)
        guard bytes.count == 80, bytes[8] == 61 else { return nil }
        let text = String(decoding: bytes[10...], as: UTF8.self)
        var result = ""
        var quoted = false
        for c in text {
            if c == "'" { quoted.toggle() }
            if c == "/" && !quoted { break }
            result.append(c)
        }
        result = result.trimmingCharacters(in: .whitespaces)
        if result.first == "'", result.last == "'", result.count >= 2 {
            result = String(result.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    init(url: URL) throws {
        self.url = url
        data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 2880 else { throw FITSError("This file is too short to be a FITS file.") }
        guard String(decoding: data.prefix(8), as: UTF8.self) == "SIMPLE  " else {
            throw FITSError("Choose an uncompressed FITS file with a SIMPLE primary header.")
        }
        var parsed: [FITSHDU] = []
        var position = 0
        while position < data.count {
            guard data.count - position >= 2880 else { throw FITSError("Incomplete FITS header block.") }
            let headerStart = position
            var cards: [String] = []
            var values: [String: String] = [:]
            var foundEnd = false
            while position + 80 <= data.count {
                let card = String(decoding: data[position..<position+80], as: UTF8.self)
                position += 80
                let key = String(card.prefix(8)).trimmingCharacters(in: .whitespaces)
                cards.append(card)
                if key == "END" { foundEnd = true; break }
                if let value = Self.value(card) { values[key] = value }
                if cards.count > 100000 { throw FITSError("FITS header exceeds the supported size.") }
            }
            guard foundEnd else { throw FITSError("FITS header has no END card.") }
            position = headerStart + ((position - headerStart + 2879) / 2880) * 2880
            guard let bitpix = Int(values["BITPIX"] ?? ""),
                  [8,16,32,64,-32,-64].contains(bitpix),
                  let naxis = Int(values["NAXIS"] ?? ""), (0...999).contains(naxis) else {
                throw FITSError("Invalid BITPIX or NAXIS in HDU \(parsed.count).")
            }
            var dimensions: [Int] = []
            var count = naxis == 0 ? 0 : 1
            if naxis > 0 {
                for axis in 1...naxis {
                    guard let size = Int(values["NAXIS\(axis)"] ?? ""), size >= 0 else {
                        throw FITSError("Invalid image dimensions in HDU \(parsed.count).")
                    }
                    let product = count.multipliedReportingOverflow(by: size)
                    guard !product.overflow else { throw FITSError("Image dimensions overflow.") }
                    count = product.partialValue
                    dimensions.append(size)
                }
            }
            let pcount = Int(values["PCOUNT"] ?? "0") ?? 0
            let gcount = Int(values["GCOUNT"] ?? "1") ?? 1
            guard pcount >= 0, gcount >= 1, count <= Int.max - pcount else { throw FITSError("Invalid FITS data size.") }
            let grouped = (count + pcount).multipliedReportingOverflow(by: gcount)
            let bytes = grouped.partialValue.multipliedReportingOverflow(by: abs(bitpix)/8)
            guard !grouped.overflow, !bytes.overflow, bytes.partialValue <= data.count - position else {
                throw FITSError("Truncated FITS data in HDU \(parsed.count).")
            }
            parsed.append(FITSHDU(index: parsed.count, cards: cards, values: values,
                                  offset: position, dimensions: dimensions, bitpix: bitpix))
            position += bytes.partialValue
            position = ((position + 2879) / 2880) * 2880
        }
        hdus = parsed
    }

    func potential() throws -> Potential {
        let candidates = hdus.filter { $0.isImage }
        guard let hdu = candidates.first(where: { $0.name.uppercased() == "V" }) ?? candidates.first else {
            throw FITSError("No two-dimensional image found. You can still inspect the headers.")
        }
        let width = hdu.dimensions[0], height = hdu.dimensions[1]
        guard width <= 16384, height <= 16384, width * height <= 32_000_000 else {
            throw FITSError("This image exceeds the viewer's 32-million-pixel limit. Headers are still available.")
        }
        let scale = hdu.number("BSCALE", 1), zero = hdu.number("BZERO", 0)
        let blank = hdu.values["BLANK"].flatMap(Int64.init)
        var values = [Double](repeating: 0, count: width * height)
        var minimum = Double.infinity, maximum = -Double.infinity, finiteCount = 0
        data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            let stride = abs(hdu.bitpix) / 8
            for i in 0..<values.count {
                let offset = hdu.offset + i * stride
                var bits: UInt64 = 0
                for j in 0..<stride { bits = (bits << 8) | UInt64(p[offset+j]) }
                let value: Double
                var integer: Int64? = nil
                switch hdu.bitpix {
                case -32: value = Double(Float(bitPattern: UInt32(bits)))
                case -64: value = Double(bitPattern: bits)
                case 8: integer = Int64(bits); value = Double(bits)
                case 16: integer = Int64(Int16(bitPattern: UInt16(bits))); value = Double(integer!)
                case 32: integer = Int64(Int32(bitPattern: UInt32(bits))); value = Double(integer!)
                default: integer = Int64(bitPattern: bits); value = Double(integer!)
                }
                let v = (integer != nil && blank != nil && integer == blank) ? Double.nan : value * scale + zero
                values[i] = v
                if v.isFinite { minimum = min(minimum, v); maximum = max(maximum, v); finiteCount += 1 }
            }
        }
        guard finiteCount > 0 else { throw FITSError("The image has no finite pixel values. Headers are still available.") }
        let lx = hdu.number("LX", hdus[0].number("LX", .nan))
        let ly = hdu.number("LY", hdus[0].number("LY", .nan))
        let hasCoordinates = lx.isFinite && ly.isFinite && lx > 0 && ly > 0
        return Potential(width: width, height: height, values: values,
                         lx: hasCoordinates ? lx : Double(width)/2,
                         ly: hasCoordinates ? ly : Double(height)/2,
                         fieldCoordinates: hasCoordinates,
                         colorLimit: max(abs(minimum),abs(maximum)) == 0 ? 1 : max(abs(minimum),abs(maximum)),
                         minimum: minimum, maximum: maximum, finiteCount: finiteCount, hduIndex: hdu.index)
    }

    func headerText(index: Int?) -> String {
        let selected = index.map { [hdus[$0]] } ?? hdus
        return selected.map { hdu in
            "HDU \(hdu.index) — \(hdu.name)\n" + String(repeating: "─", count: 80) + "\n" + hdu.cards.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
