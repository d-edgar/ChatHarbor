import Foundation
import AppKit
import CoreText

// Reports contain untrusted model output. Only generated formatting becomes HTML.
enum BrainstormReport {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    /// Convert a markdown string to a clean, print-friendly HTML document
    static func html(_ markdown: String, title: String) -> String {
        // Simple markdown → HTML conversion (handles headers, bold, lists, paragraphs, hr)
        var html = escape(markdown)

        // Convert headers (must process ### before ## before #)
        let headerPatterns: [(pattern: String, tag: String)] = [
            ("^### (.+)$", "h3"),
            ("^## (.+)$", "h2"),
            ("^# (.+)$", "h1")
        ]
        for (pattern, tag) in headerPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                html = regex.stringByReplacingMatches(
                    in: html, range: NSRange(html.startIndex..., in: html),
                    withTemplate: "<\(tag)>$1</\(tag)>"
                )
            }
        }

        // Bold: **text**
        if let boldRegex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*") {
            html = boldRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<strong>$1</strong>"
            )
        }

        // Italic: *text* (single asterisks not preceded/followed by another asterisk)
        if let italicRegex = try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)") {
            html = italicRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<em>$1</em>"
            )
        }

        // Unordered list items: - text
        if let listRegex = try? NSRegularExpression(pattern: "^- (.+)$", options: .anchorsMatchLines) {
            html = listRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<li>$1</li>"
            )
        }
        // Wrap consecutive <li> items in <ul>
        if let ulRegex = try? NSRegularExpression(pattern: "(<li>.+</li>\n?)+", options: .dotMatchesLineSeparators) {
            let matches = ulRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for match in matches.reversed() {
                if let range = Range(match.range, in: html) {
                    let listContent = String(html[range])
                    html.replaceSubrange(range, with: "<ul>\(listContent)</ul>")
                }
            }
        }

        // Numbered list items: 1. text
        if let olRegex = try? NSRegularExpression(pattern: "^\\d+\\. (.+)$", options: .anchorsMatchLines) {
            html = olRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<li>$1</li>"
            )
        }

        // Horizontal rules: ---
        if let hrRegex = try? NSRegularExpression(pattern: "^---+$", options: .anchorsMatchLines) {
            html = hrRegex.stringByReplacingMatches(
                in: html, range: NSRange(html.startIndex..., in: html),
                withTemplate: "<hr>"
            )
        }

        // Wrap remaining plain-text lines in <p> tags (lines that aren't already wrapped)
        let lines = html.components(separatedBy: "\n")
        var processedLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                processedLines.append("")
            } else if trimmed.hasPrefix("<h") || trimmed.hasPrefix("<ul") || trimmed.hasPrefix("<li")
                        || trimmed.hasPrefix("</ul") || trimmed.hasPrefix("<hr") || trimmed.hasPrefix("<ol")
                        || trimmed.hasPrefix("</ol") {
                processedLines.append(line)
            } else {
                processedLines.append("<p>\(line)</p>")
            }
        }
        html = processedLines.joined(separator: "\n")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
        <title>\(escape(title))</title>
        <style>
            @page { margin: 0.75in; }
            body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
                font-size: 12px;
                line-height: 1.6;
                color: #1d1d1f;
                max-width: 100%;
                padding: 0;
            }
            h1 {
                font-size: 22px;
                font-weight: 700;
                border-bottom: 2px solid #0071e3;
                padding-bottom: 8px;
                margin-top: 0;
                color: #1d1d1f;
            }
            h2 {
                font-size: 16px;
                font-weight: 600;
                color: #0071e3;
                margin-top: 24px;
                margin-bottom: 8px;
            }
            h3 {
                font-size: 14px;
                font-weight: 600;
                color: #1d1d1f;
                margin-top: 16px;
                margin-bottom: 6px;
            }
            p { margin: 6px 0; }
            em { color: #6e6e73; }
            ul, ol { padding-left: 20px; margin: 8px 0; }
            li { margin: 3px 0; }
            strong { color: #1d1d1f; }
            hr {
                border: none;
                border-top: 1px solid #d2d2d7;
                margin: 24px 0;
            }
        </style>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }

    @MainActor
    static func savePDF(html: String, to url: URL) throws {
        let text = try NSAttributedString(data: Data(html.utf8),
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let data = NSMutableData()
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let pdf = CGContext(consumer: consumer, mediaBox: &page, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let area = CGPath(rect: page.insetBy(dx: 54, dy: 54), transform: nil)
        var offset = 0
        repeat {
            pdf.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), area, nil)
            CTFrameDraw(frame, pdf)
            pdf.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 || text.length == 0 else {
                pdf.closePDF()
                throw CocoaError(.fileWriteUnknown)
            }
            offset += visible.length
        } while offset < text.length
        pdf.closePDF()
        try (data as Data).write(to: url, options: .atomic)
    }

}
