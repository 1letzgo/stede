import CoreTransferable
import StedeCore
import SwiftUI
import UniformTypeIdentifiers

/// Teilen wie in „SPD vor Ort“: Terminbild plus fertiger Text über das System-Teilen-Menü
/// (WhatsApp, Signal, Mail …); ohne Bild nur der Text.
enum EventShare {
    /// Text im Format von „SPD vor Ort“: Titel, Wann, Ort, Beschreibung (gekürzt), Community.
    static func text(for info: CommunityEventInfo) -> String {
        let day = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
            .weekday(.wide).day(.twoDigits).month(.twoDigits).year()
        let time = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
        var when = "\(info.starts.formatted(day)), \(info.starts.formatted(time))"
        if let ends = info.ends, IslandTime.isSameDay(ends, info.starts), ends > info.starts {
            when += "–\(ends.formatted(time))"
        }
        var parts = [info.title, "Wann: \(when) Uhr"]
        if let location = info.location, !location.isEmpty { parts.append("Ort: \(location)") }
        let description = info.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty {
            parts.append(description.count > 450 ? String(description.prefix(450)) + "…" : description)
        }
        parts.append("\(info.community) · geteilt aus der \(AppBrand.current.displayName)-App")
        return parts.joined(separator: "\n\n")
    }
}

/// Terminbild als teilbare JPEG-Datei.
struct SharedEventPhoto: Transferable {
    let jpeg: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { $0.jpeg }
            .suggestedFileName("termin.jpg")
    }
}

/// Teilen-Knopf für einen Termin: mit Bild, sobald es geladen ist, sonst nur Text.
struct EventShareButton<Label: View>: View {
    let info: CommunityEventInfo
    @ViewBuilder var label: () -> Label
    @State private var photo: PlatformImage?

    var body: some View {
        let text = EventShare.text(for: info)
        Group {
            #if canImport(UIKit)
            if let photo, let jpeg = photo.jpegData(compressionQuality: 0.9) {
                ShareLink(item: SharedEventPhoto(jpeg: jpeg), subject: Text(info.title), message: Text(text),
                          preview: SharePreview(info.title, image: Image(uiImage: photo))) { label() }
            } else {
                ShareLink(item: text, subject: Text(info.title)) { label() }
            }
            #else
            ShareLink(item: text, subject: Text(info.title)) { label() }
            #endif
        }
        .task(id: info.imageURL) {
            guard let url = info.imageURL else { photo = nil; return }
            photo = await RemoteImageCache.shared.image(for: url)
        }
    }
}
