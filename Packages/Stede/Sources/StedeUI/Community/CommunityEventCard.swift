import StedeCore
import SwiftUI

/// Die eine Terminkarte für Community-Termine — in der Community und im
/// Kalender-Tab identisch: Foto oben, Kalender-Kachel, Titel, Zeit-Pille,
/// Community-Pille (nur im Kalender), Text, Ort, Zusage-Pillen.
struct CommunityEventCard: View {
    let title: String
    /// Name der Community; nil innerhalb der Community selbst.
    let community: String?
    let starts: Date
    let ends: Date?
    let location: String?
    let description: String
    let imageURL: URL?
    let isPublic: Bool
    let isCancelled: Bool
    let participation: ParticipationStatus?
    let isSignedIn: Bool
    let onParticipate: (ParticipationStatus?) -> Void
    let signIn: () -> Void
    /// Vorhanden, wenn der Nutzer den Termin bearbeiten darf.
    var onEdit: (() -> Void)?

    private static let dateFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .weekday(.abbreviated).day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    private static let timeFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    @ScaledMetric(relativeTo: .body) private var imageHeight = 170.0

    private var tint: Color { isCancelled ? StedeTheme.harborRed : StedeTheme.seaTeal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let imageURL { EventPhoto(url: imageURL, height: imageHeight) }
            details
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard(highlighted: participation == .going)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                StedeIconChip(symbol: isCancelled ? "calendar.badge.exclamationmark" : "calendar", color: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).fontDesign(.rounded).strikethrough(isCancelled)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            StedeTagPill(text: starts.formatted(Self.dateFormat) + (ends.map { "–\($0.formatted(Self.timeFormat))" } ?? ""), color: tint)
                            if let community { StedeTagPill(text: community, color: StedeTheme.heather) }
                            if isCancelled { StedeTagPill(text: "abgesagt", color: StedeTheme.harborRed) }
                        }
                    }
                }
                Spacer(minLength: 8)
                if let onEdit {
                    Button(action: onEdit) { StedeActionChip(title: "Bearbeiten", symbol: "pencil") }
                        .buttonStyle(StedeCardButtonStyle())
                }
                // Intern: kleines Schloss oben rechts statt einer Pille.
                if !isPublic {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Nur für Mitglieder")
                }
            }
            if !description.isEmpty { Text(description).font(.subheadline).foregroundStyle(.secondary).lineLimit(4) }
            if let location, !location.isEmpty {
                Label { Text(location) } icon: { Image(systemName: "mappin.and.ellipse").foregroundStyle(tint) }.font(.caption)
            }
            if !isCancelled {
                if isSignedIn {
                    ParticipationChips(participation: participation, onParticipate: onParticipate)
                } else {
                    Button(action: signIn) {
                        StedeColorChip(title: "Anmelden, um zuzusagen", symbol: "person.crop.circle", color: StedeTheme.ink)
                    }
                    .buttonStyle(StedeCardButtonStyle())
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Foto oben in der Terminkarte, formatfüllend und an der Kartenkante beschnitten.
struct EventPhoto: View {
    let url: URL
    let height: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Rectangle().fill(StedeTheme.seaTeal.opacity(0.12))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
