import Foundation
import WebKit

/// WebKit owns frame identity and injects interception before the site's scripts.
@MainActor
final class BrowserWebKitElementHidingDocument: NSObject, WKScriptMessageHandler {
    // MARK: - Static Variables

    private static let world = WKContentWorld.world(name: "com.pixel-imagination.crest.element-hiding")
    private static let handlerName = "crestElementHiding"

    // MARK: - Variables

    private weak var webView: WKWebView?
    private let session: BrowserElementHidingSession

    // MARK: - Initializers

    init(webView: WKWebView, session: BrowserElementHidingSession) {
        self.webView = webView
        self.session = session
        super.init()
        let controller = webView.configuration.userContentController
        controller.add(self, contentWorld: Self.world, name: Self.handlerName)
        controller.addUserScript(
            WKUserScript(
                source: BrowserElementHidingJavaScript.source,
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world))
        session.connect { [weak webView] body, arguments in
            try await webView?.callAsyncJavaScript(body, arguments: arguments, in: nil, contentWorld: Self.world)
        }
    }

    // MARK: - Actions - Messages

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === webView, message.frameInfo.isMainFrame,
            let body = message.body as? String, body.utf8.count <= 8_192,
            let data = body.data(using: .utf8),
            let value = try? JSONDecoder().decode(BrowserElementHidingMessage.self, from: data)
        else { return }
        let source = message.frameInfo.securityOrigin
        guard source.protocol == "https" || source.protocol == "http", !source.host.isEmpty else { return }
        let origin = SiteOrigin(scheme: source.protocol, host: source.host, port: source.port)
        session.receive(value, origin: origin)
    }

    func stop() {
        session.disconnect()
        webView?.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.handlerName, contentWorld: Self.world)
        webView = nil
    }
}
