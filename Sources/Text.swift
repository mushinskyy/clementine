import Foundation

// MARK: - Spreadsheets (CSV / TSV / XLSX / JSON / HTML)

enum Sheet {
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if inQuotes {
                if c == "\"" {
                    let n = text.index(after: i)
                    if n < text.endIndex, text[n] == "\"" { field.append("\""); i = n }
                    else { inQuotes = false }
                } else { field.append(c) }
            } else {
                if c == "\"" { inQuotes = true }
                else if c == delimiter { row.append(field); field = "" }
                else if c == "\n" || c == "\r" {
                    if c == "\r", text.index(after: i) < text.endIndex, text[text.index(after: i)] == "\n" { i = text.index(after: i) }
                    row.append(field); field = ""; rows.append(row); row = []
                } else { field.append(c) }
            }
            i = text.index(after: i)
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func serialize(_ rows: [[String]], delimiter: Character) -> String {
        rows.map { row in
            row.map { f -> String in
                let needs = f.contains(delimiter) || f.contains("\"") || f.contains("\n") || f.contains("\r")
                return needs ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: String(delimiter))
        }.joined(separator: "\n") + "\n"
    }

    static func read(_ u: URL) throws -> [[String]] {
        let e = u.pathExtension.lowercased()
        if e == "xlsx" { return try XLSX.read(u) }
        let data = try Data(contentsOf: u)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return parse(text, delimiter: e == "tsv" ? "\t" : ",")
    }

    static func convert(_ urls: [URL], to ext: String) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let rows = try read(u)
            let out = Output.url(for: u, ext: ext)
            switch ext {
            case "csv": try serialize(rows, delimiter: ",").write(to: out, atomically: true, encoding: .utf8)
            case "tsv": try serialize(rows, delimiter: "\t").write(to: out, atomically: true, encoding: .utf8)
            case "xlsx": try XLSX.write(rows, to: out)
            case "json": try json(rows).write(to: out, atomically: true, encoding: .utf8)
            case "html": try html(rows, title: u.deletingPathExtension().lastPathComponent).write(to: out, atomically: true, encoding: .utf8)
            case "md": try markdown(rows).write(to: out, atomically: true, encoding: .utf8)
            default: throw ConvError("Unsupported spreadsheet format \(ext)")
            }
            outs.append(out)
        }
        return .files(outs)
    }

    static func json(_ rows: [[String]]) throws -> String {
        guard let header = rows.first else { return "[]" }
        var objs: [[String: Any]] = []
        for r in rows.dropFirst() {
            var o: [String: Any] = [:]
            for (i, h) in header.enumerated() {
                let v = i < r.count ? r[i] : ""
                if let d = Double(v), !v.isEmpty, !(v.hasPrefix("0") && v.count > 1 && !v.hasPrefix("0.")) { o[h] = d } else { o[h] = v }
            }
            objs.append(o)
        }
        let data = try JSONSerialization.data(withJSONObject: objs, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func html(_ rows: [[String]], title: String) -> String {
        var s = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(title.xmlEscaped)</title><style>body{font-family:-apple-system,sans-serif;padding:24px}table{border-collapse:collapse}td,th{border:1px solid #ddd;padding:6px 10px;text-align:left}th{background:#f4f4f4}</style></head><body><table>\n"
        for (i, r) in rows.enumerated() {
            let tag = i == 0 ? "th" : "td"
            s += "<tr>" + r.map { "<\(tag)>\($0.xmlEscaped)</\(tag)>" }.joined() + "</tr>\n"
        }
        return s + "</table></body></html>"
    }

    static func markdown(_ rows: [[String]]) -> String {
        guard let header = rows.first else { return "" }
        var s = "| " + header.joined(separator: " | ") + " |\n|" + header.map { _ in " --- |" }.joined() + "\n"
        for r in rows.dropFirst() { s += "| " + r.map { $0.replacingOccurrences(of: "|", with: "\\|") }.joined(separator: " | ") + " |\n" }
        return s
    }
}

enum XLSX {
    static func read(_ u: URL) throws -> [[String]] {
        let dir = try Output.tempDir()
        try Shell.run("/usr/bin/ditto", ["-x", "-k", u.path, dir.path])
        var shared: [String] = []
        if let d = try? Data(contentsOf: dir.appendingPathComponent("xl/sharedStrings.xml")) {
            let p = SharedStringsParser(); let x = XMLParser(data: d); x.delegate = p; x.parse(); shared = p.strings
        }
        let sheetURL = dir.appendingPathComponent("xl/worksheets/sheet1.xml")
        guard let d = try? Data(contentsOf: sheetURL) else { throw ConvError("No worksheet found in \(u.lastPathComponent)") }
        let p = SheetParser(shared: shared); let x = XMLParser(data: d); x.delegate = p; x.parse()
        return p.rows()
    }

    static func write(_ rows: [[String]], to out: URL) throws {
        let dir = try Output.tempDir()
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("xl/_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)
        let ct = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>
        """
        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """
        let wb = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>
        """
        let wbRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>
        """
        var sheet = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"
        for (ri, row) in rows.enumerated() {
            sheet += "<row r=\"\(ri + 1)\">"
            for (ci, v) in row.enumerated() {
                let ref = "\(columnName(ci))\(ri + 1)"
                if let _ = Double(v), !v.isEmpty, !(v.hasPrefix("0") && v.count > 1 && !v.hasPrefix("0.")) {
                    sheet += "<c r=\"\(ref)\"><v>\(v)</v></c>"
                } else if !v.isEmpty {
                    sheet += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(v.xmlEscaped)</t></is></c>"
                }
            }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"
        try ct.write(to: dir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rels.write(to: dir.appendingPathComponent("_rels/.rels"), atomically: true, encoding: .utf8)
        try wb.write(to: dir.appendingPathComponent("xl/workbook.xml"), atomically: true, encoding: .utf8)
        try wbRels.write(to: dir.appendingPathComponent("xl/_rels/workbook.xml.rels"), atomically: true, encoding: .utf8)
        try sheet.write(to: dir.appendingPathComponent("xl/worksheets/sheet1.xml"), atomically: true, encoding: .utf8)
        try Shell.run("/usr/bin/zip", ["-r", "-X", "-q", out.path, "[Content_Types].xml", "_rels", "xl"], cwd: dir)
    }

    static func columnName(_ i: Int) -> String {
        var n = i, s = ""
        repeat { s = String(UnicodeScalar(65 + n % 26)!) + s; n = n / 26 - 1 } while n >= 0
        return s
    }

    static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for c in ref.uppercased() where c.isLetter { n = n * 26 + Int(c.asciiValue! - 64) }
        return max(0, n - 1)
    }

    final class SharedStringsParser: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current = ""
        private var inT = false
        private var inSI = false
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if e == "si" { inSI = true; current = "" }
            if e == "t" { inT = true }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if inT { current += s } }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            if e == "t" { inT = false }
            if e == "si" { strings.append(current); inSI = false }
        }
    }

    final class SheetParser: NSObject, XMLParserDelegate {
        let shared: [String]
        init(shared: [String]) { self.shared = shared }
        private var cells: [Int: [Int: String]] = [:]
        private var row = 0, col = 0
        private var type = ""
        private var value = ""
        private var capture = false
        func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String]) {
            switch e {
            case "row": row = Int(a["r"] ?? "") ?? row + 1; col = -1
            case "c":
                if let r = a["r"] { col = XLSX.columnIndex(r) } else { col += 1 }
                type = a["t"] ?? ""; value = ""
            case "v", "t": capture = true
            default: break
            }
        }
        func parser(_ p: XMLParser, foundCharacters s: String) { if capture { value += s } }
        func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
            if e == "v" || e == "t" { capture = false }
            if e == "c" {
                var v = value
                if type == "s", let i = Int(value), i < shared.count { v = shared[i] }
                if type == "b" { v = value == "1" ? "TRUE" : "FALSE" }
                if !v.isEmpty { cells[row, default: [:]][col] = v }
            }
        }
        func rows() -> [[String]] {
            guard let maxRow = cells.keys.max() else { return [] }
            let maxCol = cells.values.flatMap { $0.keys }.max() ?? 0
            return (1...maxRow).map { r in (0...maxCol).map { cells[r]?[$0] ?? "" } }
        }
    }
}

// MARK: - Subtitles

enum Subs {
    static func convert(_ urls: [URL], to ext: String) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            let text = try String(contentsOf: u, encoding: .utf8)
            let out = Output.url(for: u, ext: ext)
            let result: String
            switch ext {
            case "vtt": result = toVTT(text)
            case "srt": result = toSRT(text)
            default: result = toText(text)
            }
            try result.write(to: out, atomically: true, encoding: .utf8)
            outs.append(out)
        }
        return .files(outs)
    }

    static let timeLine = try! NSRegularExpression(pattern: "^\\s*\\d{1,2}:\\d{2}:\\d{2}[,.]\\d{3}\\s*-->\\s*\\d{1,2}:\\d{2}:\\d{2}[,.]\\d{3}")

    static func isTime(_ l: String) -> Bool { timeLine.firstMatch(in: l, range: NSRange(l.startIndex..., in: l)) != nil || l.contains("-->") }

    static func toVTT(_ s: String) -> String {
        if s.hasPrefix("WEBVTT") { return s }
        let lines = s.components(separatedBy: .newlines).map { l -> String in
            isTime(l) ? l.replacingOccurrences(of: ",", with: ".") : l
        }
        return "WEBVTT\n\n" + lines.joined(separator: "\n")
    }

    static func toSRT(_ s: String) -> String {
        var blocks: [[String]] = []
        var cur: [String] = []
        for l in s.components(separatedBy: .newlines) {
            if l.trimmingCharacters(in: .whitespaces).isEmpty { if !cur.isEmpty { blocks.append(cur); cur = [] } }
            else { cur.append(l) }
        }
        if !cur.isEmpty { blocks.append(cur) }
        var out = "", n = 1
        for b in blocks {
            guard let ti = b.firstIndex(where: isTime) else { continue }
            let time = b[ti].replacingOccurrences(of: ".", with: ",")
            let body = b[(ti + 1)...].joined(separator: "\n")
            out += "\(n)\n\(time)\n\(body)\n\n"; n += 1
        }
        return out
    }

    static func toText(_ s: String) -> String {
        s.components(separatedBy: .newlines)
            .filter { !isTime($0) && Int($0.trimmingCharacters(in: .whitespaces)) == nil && !$0.hasPrefix("WEBVTT") && !$0.hasPrefix("NOTE") }
            .map { $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }
}

// MARK: - Archives

enum Arch {
    static func zip(_ urls: [URL]) throws -> Outcome {
        let out = outName(urls, ext: "zip")
        let parent = urls[0].deletingLastPathComponent()
        let sameParent = urls.allSatisfy { $0.deletingLastPathComponent() == parent }
        if sameParent {
            try Shell.run("/usr/bin/zip", ["-r", "-y", "-q", out.path] + urls.map(\.lastPathComponent), cwd: parent)
        } else {
            try Shell.run("/usr/bin/zip", ["-r", "-y", "-q", "-j", out.path] + urls.map(\.path))
        }
        return .files([out])
    }

    static func tar(_ urls: [URL], gzip: Bool) throws -> Outcome {
        let out = outName(urls, ext: gzip ? "tar.gz" : "tar")
        let parent = urls[0].deletingLastPathComponent()
        try Shell.run("/usr/bin/tar", [gzip ? "-czf" : "-cf", out.path, "-C", parent.path] + urls.map(\.lastPathComponent))
        return .files([out])
    }

    static func extract(_ urls: [URL]) throws -> Outcome {
        var outs: [URL] = []
        for u in urls {
            var name = u.deletingPathExtension()
            if name.pathExtension.lowercased() == "tar" { name = name.deletingPathExtension() }
            let dir = Output.folder(for: name, suffix: "")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Shell.run("/usr/bin/tar", ["-xf", u.path, "-C", dir.path])
            outs.append(dir)
        }
        return .files(outs)
    }

    private static func outName(_ urls: [URL], ext: String) -> URL {
        let suffix = urls.count > 1 ? " and \(urls.count - 1) more" : ""
        let first = urls[0]
        let dir = Prefs.shared.output.directory ?? first.deletingLastPathComponent()
        let base = (Kinds.kind(of: first) == .folder ? first.lastPathComponent : first.deletingPathExtension().lastPathComponent) + suffix
        return Output.unique(dir.appendingPathComponent(base + "." + ext))
    }
}
