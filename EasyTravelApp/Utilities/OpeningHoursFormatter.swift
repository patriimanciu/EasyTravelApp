import Foundation

enum OpeningHoursFormatter {
    enum Day: Int, CaseIterable {
        case mon = 0, tue, wed, thu, fri, sat, sun

        var short: String {
            switch self {
            case .mon: "Mon"
            case .tue: "Tue"
            case .wed: "Wed"
            case .thu: "Thu"
            case .fri: "Fri"
            case .sat: "Sat"
            case .sun: "Sun"
            }
        }

        static func parsePrefix(_ raw: String) -> Day? {
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if s.hasPrefix("mon") { return .mon }
            if s.hasPrefix("tue") { return .tue }
            if s.hasPrefix("wed") { return .wed }
            if s.hasPrefix("thu") { return .thu }
            if s.hasPrefix("fri") { return .fri }
            if s.hasPrefix("sat") { return .sat }
            if s.hasPrefix("sun") { return .sun }
            return nil
        }
    }

    static func displayLines(openingHours: [String]?, category: LocationItem.Category) -> [String] {
        // Public spaces: if we have no structured hours at all, default to open 24h.
        if (openingHours ?? []).isEmpty, isLikelyAlwaysOpen(category: category) {
            return ["Open 24h"]
        }

        let rawLines = (openingHours ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if rawLines.isEmpty { return [] }

        // If everything says open 24 hours, show a single summary.
        if rawLines.allSatisfy({ normalizeValue(stripDayPrefixIfPresent($0)).contains("24") && normalizeValue(stripDayPrefixIfPresent($0)).contains("open") }) {
            return ["Open 24h"]
        }

        // Parse into weekday map if possible. Otherwise, show raw (multi-line but still clean).
        let parsed = parseWeekdayMap(from: rawLines)
        guard let weekdayMap = parsed else {
            return rawLines
        }

        return groupWeekdays(weekdayMap)
    }

    static func summary(openingHours: [String]?, category: LocationItem.Category) -> String {
        let lines = displayLines(openingHours: openingHours, category: category)
        if lines.isEmpty { return "—" }
        if lines.count == 1 { return lines[0] }
        // Short summary: first 2 groups + ellipsis.
        if lines.count == 2 { return "\(lines[0]) • \(lines[1])" }
        return "\(lines[0]) • \(lines[1]) • …"
    }

    /// One-line condensed hours for trip list rows (e.g. `Mon–Fri: 8:00 AM - 8:00 PM • Sat–Sun: 10:00 AM - 6:00 PM`).
    static func condensedListLine(openingHours: [String]?, category: LocationItem.Category) -> String? {
        let lines = displayLines(openingHours: openingHours, category: category)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: " · ")
    }

    private static func isLikelyAlwaysOpen(category: LocationItem.Category) -> Bool {
        switch category {
        case .park, .neighborhood:
            return true
        default:
            return false
        }
    }

    private static func stripDayPrefixIfPresent(_ line: String) -> String {
        // "Monday: 9–5" -> "9–5"
        if let idx = line.firstIndex(of: ":") {
            let prefix = String(line[..<idx])
            if Day.parsePrefix(prefix) != nil || prefix.lowercased().hasPrefix("monday") || prefix.lowercased().hasPrefix("tuesday") {
                return String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return line
    }

    private static func normalizeValue(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "—", with: "-")
        s = s.replacingOccurrences(of: "–", with: "-")
        s = s.replacingOccurrences(of: " to ", with: " - ", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "open 24 hours", with: "open 24h", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "open 24h", with: "Open 24h", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "closed", with: "Closed", options: .caseInsensitive)
        s = s.replacingOccurrences(of: " ", with: " ")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseWeekdayMap(from lines: [String]) -> [Day: String]? {
        var out: [Day: String] = [:]

        for line in lines {
            // Accept "Monday: ..." or "Mon: ..."
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let left = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            let day: Day?
            if let d = Day.parsePrefix(left) {
                day = d
            } else {
                let l = left.lowercased()
                if l.hasPrefix("monday") { day = .mon }
                else if l.hasPrefix("tuesday") { day = .tue }
                else if l.hasPrefix("wednesday") { day = .wed }
                else if l.hasPrefix("thursday") { day = .thu }
                else if l.hasPrefix("friday") { day = .fri }
                else if l.hasPrefix("saturday") { day = .sat }
                else if l.hasPrefix("sunday") { day = .sun }
                else { day = nil }
            }
            guard let day else { return nil }
            out[day] = normalizeValue(right.isEmpty ? "Closed" : right)
        }

        // If we didn't get at least 5 weekdays, treat as not-structured (avoid weird partial results).
        if out.count < 5 { return nil }
        return out
    }

    private static func groupWeekdays(_ map: [Day: String]) -> [String] {
        // Fill missing days (if any) as unknown; we avoid grouping unknowns.
        var values: [String] = []
        values.reserveCapacity(7)
        for d in Day.allCases {
            values.append(map[d] ?? "")
        }

        func label(_ start: Int, _ end: Int) -> String {
            let ds = Day(rawValue: start)!.short
            let de = Day(rawValue: end)!.short
            return start == end ? ds : "\(ds)–\(de)"
        }

        // Special: Mon closed + Tue–Sun same.
        if values[0].caseInsensitiveCompare("Closed") == .orderedSame,
           Set(values[1...6]).count == 1,
           let common = values[1...6].first,
           !common.isEmpty {
            return ["Mon: Closed", "Tue–Sun: \(common)"]
        }

        // General grouping: consecutive runs with same value.
        var groups: [(start: Int, end: Int, value: String)] = []
        var i = 0
        while i < values.count {
            let v = values[i]
            var j = i
            while j + 1 < values.count && values[j + 1] == v {
                j += 1
            }
            groups.append((i, j, v))
            i = j + 1
        }

        // Render with preference: Mon–Fri, Sat, Sun when those are equal.
        let monFri = values[0...4]
        if Set(monFri).count == 1,
           values[5] == values[6],
           let mf = monFri.first,
           !mf.isEmpty {
            let satSun = values[5]
            if satSun == mf {
                return ["Mon–Sun: \(mf)"]
            }
            if satSun.isEmpty {
                return ["Mon–Fri: \(mf)"]
            }
            return ["Mon–Fri: \(mf)", "Sat–Sun: \(satSun)"]
        }

        return groups.compactMap { g in
            let v = g.value
            if v.isEmpty { return nil }
            return "\(label(g.start, g.end)): \(v)"
        }
    }
}

