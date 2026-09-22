import StedeCore
import SwiftUI

/// Die eine Terminkarte für Community-Termine — in der Community und im
/// Kalender-Tab identisch: Foto oben, Kalender-Kachel, Titel, Zeit-Pille,
/// Community-Pille (nur im Kalender), Text, Ort, Zusage-Pillen.
struct CommunityEventCard: View {
    let title: String
    /// Name der Community (für Initialen, wenn kein Logo).
    let community: String
    let communityLogoURL: URL?
    let starts: Date
    let ends: Date?
    let location: String?
    let description: String
    let imageURL: URL?
    let isPublic: Bool
    let isCancelled: Bool
    /// Gesuchte Helfer (0 = keine) und Stand.
    var helpersNeeded = 0
    var helperCount = 0
    let participation: MyParticipation?
    let isSignedIn: Bool
    /// Status und Helfer-Flag; nil löscht die Zusage.
    let onParticipate: (ParticipationStatus?, Bool) -> Void
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
        .stedeCard(highlighted: participation?.status == .going)
    }

    private var isHelping: Bool { participation?.helping == true }
    private var helpersOpen: Bool { helpersNeeded > 0 && helperCount < helpersNeeded }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CommunityAvatar(logoURL: communityLogoURL, name: community)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).fontDesign(.rounded).strikethrough(isCancelled)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            StedeTagPill(text: starts.formatted(Self.dateFormat) + (ends.map { "–\($0.formatted(Self.timeFormat))" } ?? ""), color: tint)
                            if isCancelled { StedeTagPill(text: "abgesagt", color: StedeTheme.harborRed) }
                            if helpersNeeded > 0 {
                                StedeTagPill(text: helperCount >= helpersNeeded ? "Helfer komplett" : "Helfer \(helperCount)/\(helpersNeeded)", color: helperCount >= helpersNeeded ? StedeTheme.duneGreen : StedeTheme.heather)
                            }
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
                    ParticipationChips(participation: participation?.status) { status in
                        onParticipate(status, isHelping && status != nil && status != .declined)
                    }
                    // Mithelfen: sichtbar, solange Plätze frei sind oder man selbst hilft.
                    if helpersNeeded > 0, helpersOpen || isHelping {
                        Button {
                            if isHelping {
                                onParticipate(participation?.status ?? .going, false)
                            } else {
                                onParticipate(participation?.status == .declined ? .going : (participation?.status ?? .going), true)
                            }
                        } label: {
                            StedeColorChip(title: isHelping ? "Ich helfe mit" : "Mithelfen", symbol: "hands.sparkles.fill", color: StedeTheme.heather, isSelected: isHelping)
                        }
                        .buttonStyle(StedeCardButtonStyle())
                        .accessibilityAddTraits(isHelping ? .isSelected : [])
                    }
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
