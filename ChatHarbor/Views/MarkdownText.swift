import SwiftUI

// MARK: - Markdown Text View
//
// Renders markdown content with proper support for headers, lists,
// bold/italic, code blocks, and tables. Falls back to AttributedString
// for inline formatting and uses custom views for block-level elements.

struct MarkdownText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(parseBlocks(content).enumerated()), id: \.offset) { _, block in
                blockView(for: block)
            }
        }
    }

    // MARK: - Block Types

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case table(headers: [String], rows: [[String]])
        case codeBlock(language: String?, code: String)
        case divider
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)

        case .paragraph(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(inlineMarkdown(text))
                    .font(.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .codeBlock(_, let code):
            Text(code)
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                .textSelection(.enabled)

        case .divider:
            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Heading View

    private func headingView(level: Int, text: String) -> some View {
        Text(inlineMarkdown(text))
            .font(headingFont(level: level))
            .fontWeight(.semibold)
            .padding(.top, level <= 2 ? 6 : 2)
            .textSelection(.enabled)
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    // MARK: - Table View

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { i in
                    Text(inlineMarkdown(headers[i]))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.gray.opacity(0.08))

            Divider()

            // Data rows
            ForEach(rows.indices, id: \.self) { rowIdx in
                let row = rows[rowIdx]
                HStack(spacing: 0) {
                    ForEach(row.indices, id: \.self) { colIdx in
                        Text(inlineMarkdown(row[colIdx]))
                            .font(.system(size: 12))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .background(rowIdx % 2 == 0 ? Color.clear : Color.gray.opacity(0.03))

                if rowIdx < rows.count - 1 {
                    Divider().opacity(0.5)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Inline Markdown

    /// Parse inline markdown (bold, italic, code, links) using AttributedString
    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }

    // MARK: - Block Parser

    private func parseBlocks(_ text: String) -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [Block] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Divider: --- or ***
            if trimmed.count >= 3 && (trimmed.allSatisfy({ $0 == "-" }) || trimmed.allSatisfy({ $0 == "*" })) {
                blocks.append(.divider)
                i += 1
                continue
            }

            // Heading: # ## ### ####
            if let headingMatch = parseHeading(trimmed) {
                blocks.append(.heading(level: headingMatch.level, text: headingMatch.text))
                i += 1
                continue
            }

            // Code block: ```
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                i += 1 // skip closing ```
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Table: starts with | and next line is |---|
            if trimmed.hasPrefix("|") && i + 1 < lines.count {
                let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.contains("---") && nextTrimmed.hasPrefix("|") {
                    // Parse table
                    let headers = parseTableRow(trimmed)
                    i += 2 // skip header and separator
                    var rows: [[String]] = []
                    while i < lines.count {
                        let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                        guard rowLine.hasPrefix("|") else { break }
                        rows.append(parseTableRow(rowLine))
                        i += 1
                    }
                    blocks.append(.table(headers: headers, rows: rows))
                    continue
                }
            }

            // Regular paragraph — accumulate consecutive non-empty lines
            if !trimmed.isEmpty {
                var paraLines: [String] = [line]
                i += 1
                while i < lines.count {
                    let nextLine = lines[i]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    // Stop at empty lines, headings, tables, code blocks, dividers
                    if nextTrimmed.isEmpty
                        || nextTrimmed.hasPrefix("#")
                        || nextTrimmed.hasPrefix("```")
                        || (nextTrimmed.hasPrefix("|") && i + 1 < lines.count && lines[i + 1].contains("---"))
                        || (nextTrimmed.count >= 3 && nextTrimmed.allSatisfy({ $0 == "-" || $0 == "*" })) {
                        break
                    }
                    paraLines.append(nextLine)
                    i += 1
                }
                blocks.append(.paragraph(text: paraLines.joined(separator: "\n")))
            } else {
                i += 1
            }
        }

        return blocks
    }

    private func parseHeading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for char in line {
            if char == "#" { level += 1 }
            else { break }
        }
        guard level > 0 && level <= 6 else { return nil }
        let text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    private func parseTableRow(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Split by | and filter empty first/last from leading/trailing pipes
        let parts = trimmed.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Drop first and last if empty (from leading/trailing |)
        var result = parts
        if result.first?.isEmpty == true { result.removeFirst() }
        if result.last?.isEmpty == true { result.removeLast() }
        return result
    }
}
