import AppKit
import PDFKit

@main
struct PDFSmoke {
    @MainActor static func main() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ChatHarbor-PDF-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: destination) }
        let text = (1...150).map { "Paragraph \($0): A complete brainstorm report must preserve every contribution." }.joined(separator: "\n\n") + "\n\nFINAL-MARKER"
        let html = BrainstormReport.html(text, title: "Pagination regression")
        try BrainstormReport.savePDF(html: html, to: destination)
        guard let pdf = PDFDocument(url: destination), pdf.pageCount > 1,
              pdf.string?.contains("FINAL-MARKER") == true else {
            preconditionFailure("PDF export did not preserve all pages")
        }
        precondition((1...150).allSatisfy { pdf.string?.contains("Paragraph \($0):") == true })
        print("PASS: paginated PDF contains \(pdf.pageCount) pages and its final paragraph")
    }
}
