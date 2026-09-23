import CryptoKit
import SwiftUI
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

/// Bilder aus dem Backend (Termin-Fotos, Community-Logos, Profilbilder) im Speicher
/// und im Caches-Ordner. Die Pfade enthalten eine UUID und ändern sich nie — ein
/// geladenes Bild bleibt gültig; ersetzte Bilder bekommen einen neuen Pfad.
/// `AsyncImage` allein reichte nicht: der System-`URLCache` ist zu klein für Fotos.
nonisolated final class RemoteImageCache: @unchecked Sendable {
    static let shared = RemoteImageCache()

    private let memory = NSCache<NSURL, PlatformImage>()
    private let directory: URL
    private let lock = NSLock()
    private var running: [URL: Task<PlatformImage?, Never>] = [:]

    private init() {
        memory.countLimit = 200
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Einmal pro Start: Bilder, die seit 90 Tagen niemand neu geladen hat, verwerfen.
        let directory = directory
        Task.detached(priority: .background) {
            let limit = Date().addingTimeInterval(-90 * 24 * 3600)
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if date < limit { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    /// Sofort verfügbar, wenn das Bild in dieser Sitzung schon gezeigt wurde.
    func cached(_ url: URL) -> PlatformImage? {
        memory.object(forKey: url as NSURL)
    }

    /// Aus dem Speicher, sonst von der Platte, sonst aus dem Netz (und dann auf die Platte).
    /// Gleichzeitige Anfragen für dieselbe URL teilen sich einen Download.
    func image(for url: URL) async -> PlatformImage? {
        if let hit = cached(url) { return hit }
        let task: Task<PlatformImage?, Never> = lock.withLock {
            if let existing = running[url] { return existing }
            let task = Task { await self.load(url) }
            running[url] = task
            return task
        }
        let image = await task.value
        lock.withLock { running[url] = nil }
        return image
    }

    private func load(_ url: URL) async -> PlatformImage? {
        let file = directory.appending(path: Self.key(for: url))
        if let data = try? Data(contentsOf: file), let image = PlatformImage(data: data) {
            // Zugriff vermerken, damit oft gezeigte Bilder die 90-Tage-Grenze nicht erreichen.
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            memory.setObject(image, forKey: url as NSURL)
            return image
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = PlatformImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        memory.setObject(image, forKey: url as NSURL)
        return image
    }

    private static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Ersatz für `AsyncImage` mit dauerhaftem Cache; zeigt `placeholder`, bis das Bild da ist.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: PlatformImage?

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
        // Schon im Speicher: ohne Aufblitzen des Platzhalters anzeigen.
        _image = State(initialValue: url.flatMap { RemoteImageCache.shared.cached($0) })
    }

    var body: some View {
        Group {
            if let image {
                #if canImport(UIKit)
                Image(uiImage: image).resizable().scaledToFill()
                #else
                Image(nsImage: image).resizable().scaledToFill()
                #endif
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = RemoteImageCache.shared.cached(url) { image = hit; return }
            image = nil
            image = await RemoteImageCache.shared.image(for: url)
        }
    }
}
