import SwiftUI
import StedeCore

#if canImport(SafariServices)
import SafariServices
#endif
#if canImport(WebKit)
import WebKit
#endif

struct BrowserPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Öffnet eine URL innerhalb der App statt im externen Browser.
struct InAppBrowser: View {
    let url: URL

    var body: some View {
        #if os(iOS)
        SafariBrowser(url: url)
            .ignoresSafeArea()
        #else
        EmbeddedWebBrowser(url: url)
        #endif
    }
}

#if os(iOS)
private struct SafariBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

#if os(macOS)
private struct EmbeddedWebBrowser: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MacWebView(url: url)
                .ignoresSafeArea()
                .navigationTitle(url.host() ?? "Veranstaltung")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schließen") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 640, minHeight: 720)
    }
}

private struct MacWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
