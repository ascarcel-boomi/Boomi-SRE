import Foundation

/// Parses the text output of Python analytics scripts into structured ReportResult data.
///
/// Most scripts print tables and statistics to stdout. This parser extracts numeric data
/// from common patterns: "Label: 123", "Label — 45%", table rows with numbers, etc.
struct OutputParser {

    /// Parse raw script output into a ReportResult.
    static func parse(output: String, report: ReportItem) -> ReportResult {
        let lines = output.components(separatedBy: "\n")
        var sections: [ResultSection] = []

        // Strategy: look for section headers (lines starting with === or --- or ALL CAPS)
        // then extract key-value pairs and table rows within each section
        var currentTitle = report.title
        var currentRows: [ResultRow] = []
        let currentChartHint = report.chartType

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Section dividers
            if trimmed.hasPrefix("===") || trimmed.hasPrefix("---") {
                if !currentRows.isEmpty {
                    sections.append(ResultSection(title: currentTitle, rows: currentRows,
                                                  chartHint: currentChartHint))
                    currentRows = []
                }
                continue
            }

            // Section headers (ALL CAPS or Title Case followed by colon)
            if trimmed.count > 3 && trimmed == trimmed.uppercased() && !trimmed.contains(":") &&
                trimmed.rangeOfCharacter(from: .letters) != nil && !trimmed.hasPrefix("|") {
                if !currentRows.isEmpty {
                    sections.append(ResultSection(title: currentTitle, rows: currentRows,
                                                  chartHint: currentChartHint))
                    currentRows = []
                }
                currentTitle = trimmed.capitalized
                continue
            }

            // "Label: 123" or "Label: $1,234.56" patterns
            if let match = extractLabelValue(from: trimmed) {
                currentRows.append(match)
                continue
            }

            // "Label — 45 (32%)" patterns
            if let match = extractDashPattern(from: trimmed) {
                currentRows.append(match)
                continue
            }

            // Table row: "| col1 | col2 | col3 |"
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if let match = extractTableRow(from: trimmed) {
                    currentRows.append(match)
                }
                continue
            }

            // "  Label    123" (whitespace-aligned columns)
            if let match = extractAlignedColumns(from: trimmed) {
                currentRows.append(match)
                continue
            }
        }

        // Flush last section
        if !currentRows.isEmpty {
            sections.append(ResultSection(title: currentTitle, rows: currentRows,
                                          chartHint: currentChartHint))
        }

        // If no structured data was extracted, create a single raw text section
        if sections.isEmpty {
            sections.append(ResultSection(
                title: report.title,
                rows: [ResultRow(label: "Raw Output", value: 0, detail: output)],
                chartHint: .table
            ))
        }

        return ReportResult(title: report.title, generatedAt: Date(),
                            sections: sections, rawOutput: output)
    }

    // MARK: - Extraction Helpers

    /// Match "Label: 123" or "Label: $1,234.56"
    private static func extractLabelValue(from line: String) -> ResultRow? {
        guard let colonRange = line.range(of: ": ") else { return nil }
        let label = String(line[line.startIndex..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rest = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        guard !label.isEmpty else { return nil }

        if let value = parseNumber(rest) {
            return ResultRow(label: label, value: value, detail: rest)
        }
        // If no numeric value but there's content, store as detail-only row
        if !rest.isEmpty && label.count < 60 {
            return ResultRow(label: label, value: 0, detail: rest)
        }
        return nil
    }

    /// Match "Label — 45 (32%)" or "Label - 123"
    private static func extractDashPattern(from line: String) -> ResultRow? {
        // Try em-dash first, then en-dash, then regular dash with spaces
        for separator in [" — ", " – ", " - "] {
            guard let range = line.range(of: separator) else { continue }
            let label = String(line[line.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)

            guard !label.isEmpty, label.count < 80 else { continue }

            if let value = parseNumber(rest) {
                return ResultRow(label: label, value: value, detail: rest)
            }
        }
        return nil
    }

    /// Extract data from a markdown table row "| col1 | col2 | col3 |"
    private static func extractTableRow(from line: String) -> ResultRow? {
        let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 2 else { return nil }

        // Skip header divider rows (----)
        if cells.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" }) }) { return nil }

        let label = cells[0]
        guard !label.isEmpty else { return nil }

        // Find the first numeric cell
        for i in 1..<cells.count {
            if let value = parseNumber(cells[i]) {
                let detail = cells.dropFirst().joined(separator: " | ")
                return ResultRow(label: label, value: value, detail: detail)
            }
        }

        // All text — store with zero value for table view
        let detail = cells.dropFirst().joined(separator: " | ")
        return ResultRow(label: label, value: 0, detail: detail)
    }

    /// Match whitespace-aligned columns: "  EC2    $1,234.56"
    private static func extractAlignedColumns(from line: String) -> ResultRow? {
        // Need at least 2+ spaces separating label from value
        let pattern = #"^(.+?)\s{2,}([\$]?[\d,]+\.?\d*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }

        guard let labelRange = Range(match.range(at: 1), in: line),
              let valueRange = Range(match.range(at: 2), in: line) else { return nil }

        let label = String(line[labelRange]).trimmingCharacters(in: .whitespaces)
        let valueStr = String(line[valueRange])

        guard !label.isEmpty, let value = parseNumber(valueStr) else { return nil }

        return ResultRow(label: label, value: value, detail: valueStr)
    }

    /// Parse a number from a string, handling $, commas, and percentages.
    static func parseNumber(_ s: String) -> Double? {
        var cleaned = s.trimmingCharacters(in: .whitespaces)

        // Remove leading $ and trailing %
        if cleaned.hasPrefix("$") { cleaned = String(cleaned.dropFirst()) }
        if cleaned.hasSuffix("%") { cleaned = String(cleaned.dropLast()) }

        // Extract first number-like substring
        let pattern = #"[\d,]+\.?\d*"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
              let range = Range(match.range, in: cleaned) else { return nil }

        let numStr = String(cleaned[range]).replacingOccurrences(of: ",", with: "")
        return Double(numStr)
    }
}
