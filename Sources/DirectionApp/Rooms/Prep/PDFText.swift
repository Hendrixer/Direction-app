import Foundation
import PDFKit

/// The words of a PDF script, page by page.
enum PDFText {
    static func string(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        return (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n\n")
    }
}
