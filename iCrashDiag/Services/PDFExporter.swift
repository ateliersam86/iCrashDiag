import WebKit
import AppKit

/// Converts HTML to PDF using an off-screen WKWebView.
@MainActor
final class PDFExporter: NSObject, WKNavigationDelegate {

    private let webView: WKWebView
    private var continuation: CheckedContinuation<Data, Error>?

    override init() {
        // A4 dimensions in points (1pt = 1/72 inch)
        let a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
        webView = WKWebView(frame: a4)
        super.init()
        webView.navigationDelegate = self
    }

    /// Renders `html` and returns PDF data.
    func export(html: String) async throws -> Data {
        return try await withCheckedThrowingContinuation { [weak self] cont in
            guard let self else {
                cont.resume(throwing: ExportError.unavailable)
                return
            }
            continuation = cont
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let config = WKPDFConfiguration()
                config.rect = webView.bounds
                let data = try await webView.pdf(configuration: config)
                continuation?.resume(returning: data)
            } catch {
                continuation?.resume(throwing: error)
            }
            continuation = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    enum ExportError: Error {
        case unavailable
    }
}
