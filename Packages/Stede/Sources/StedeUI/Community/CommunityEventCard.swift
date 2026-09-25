import StedeCore
import SwiftUI

/// Was Karte und Detailansicht über einen Community-Termin wissen müssen —
/// aus `CommunityEvent` (Mitglied) oder `PublicEvent` (Kalender) gebaut.
struct CommunityEventInfo: Identifiable, Hashable {
    let id: UUID
    let title: String
    let community: String
    let communityLogoURL: URL?
    let starts: Date
    let ends: Date?
    let location: String?
    let description: String
    let imageURL: URL?
    let isPublic: Bool
    let isCancelled: Bool
    let helpersNeeded: Int
    let createdBy: UUID?
    let communityId: UUID?

    init(_ event: CommunityEvent) {
        id = event.id; title = event.title; community = event.communityName; communityLogoURL = event.communityLogoURL
        starts = event.startsAt; ends = event.endsAt; location = event.location; description = event.description
        imageURL = event.imageURL; isPublic = event.isPublic; isCancelled = event.cancelledAt != nil
        helpersNeeded = event.helpersNeeded; createdBy = event.createdBy; communityId = event.communityId
    }

    init(_ event: PublicEvent) {
        id = event.id; title = event.title; community = event.communityName; communityLogoURL = event.communityLogoURL
        starts = event.startsAt; ends = event.endsAt; location = event.location; description = event.description
        imageURL = event.imageURL; isPublic = true; isCancelled = false
        helpersNeeded = event.helpersNeeded; createdBy = nil; communityId = nil
    }

    static let dateFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .weekday(.abbreviated).day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    static let longDateFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .weekday(.wide).day().month(.wide).year().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
    static let timeFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    var timeLabel: String { starts.formatted(Self.dateFormat) + (ends.map { "–\($0.formatted(Self.timeFormat))" } ?? "") }
    /// Nur die Uhrzeit — für Listen, die schon nach Tag gegliedert sind.
    var clockLabel: String { starts.formatted(Self.timeFormat) + (ends.map { "–\($0.formatted(Self.timeFormat))" } ?? "") }
    var longTimeLabel: String { starts.formatted(Self.longDateFormat) + (ends.map { " bis \($0.formatted(Self.timeFormat)) Uhr" } ?? " Uhr") }
}

/// Die eine Terminkarte für Community-Termine — in der Community und im
/// Kalender-Tab identisch: Foto oben, Logo, Titel, Zeit-Pille, Text, Ort,
/// Zusage-Pillen, Mithelfen. Tipp auf die Karte öffnet die Detailansicht.
struct CommunityEventCard: View {
    let info: CommunityEventInfo
    var helperCount = 0
    let participation: MyParticipation?
    let isSignedIn: Bool
    /// Status und Helfer-Flag; nil löscht die Zusage.
    let onParticipate: (ParticipationStatus?, Bool) -> Void
    let signIn: () -> Void
    /// Vorhanden, wenn der Nutzer den Termin bearbeiten darf.
    var onEdit: (() -> Void)?
    var onOpen: (() -> Void)?
    /// Foto als Kopf der Karte, wo vorhanden.
    var showsPhoto = true
    /// In tagesweise gegliederten Listen reicht die Uhrzeit.
    var showsDate = true

    @ScaledMetric(relativeTo: .body) private var imageHeight = 170.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPhoto, let imageURL = info.imageURL { EventPhoto(url: imageURL, height: imageHeight) }
            EventBody(info: info, helperCount: helperCount, participation: participation, isSignedIn: isSignedIn,
                      onParticipate: onParticipate, signIn: signIn, onEdit: onEdit, compact: true, showsDate: showsDate)
                .padding(StedeTheme.cardPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .stedeCard()
        .goingOutline(participation?.status == .going)
        // Karte öffnet die Details; Chips bleiben eigene Ziele.
        .contentShape(StedeTheme.cardShape)
        .onTapGesture { onOpen?() }
        .accessibilityAction(named: "Details öffnen") { onOpen?() }
        // Langes Drücken: teilen wie in der Detailansicht.
        .contextMenu {
            EventShareButton(info: info) { Label("Teilen", systemImage: "square.and.arrow.up") }
        }
    }
}

/// Inhalt unter dem Foto — in Karte (gekürzt) und Detailansicht (voll) gleich aufgebaut.
private struct EventBody: View {
    let info: CommunityEventInfo
    let helperCount: Int
    let participation: MyParticipation?
    let isSignedIn: Bool
    let onParticipate: (ParticipationStatus?, Bool) -> Void
    let signIn: () -> Void
    var onEdit: (() -> Void)?
    let compact: Bool
    var showsDate = true

    private var tint: Color { info.isCancelled ? StedeTheme.harborRed : StedeTheme.seaTeal }
    private var isHelping: Bool { participation?.helping == true }
    private var helpersOpen: Bool { info.helpersNeeded > 0 && helperCount < info.helpersNeeded }
    /// Vorbei, sobald Ende (oder Beginn ohne Ende) verstrichen ist — dann keine Zusagen mehr.
    private var isPast: Bool { (info.ends ?? info.starts) < Date() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CommunityAvatar(logoURL: info.communityLogoURL, name: info.community)
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.title).font(.headline).fontDesign(.rounded).strikethrough(info.isCancelled)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            StedeTagPill(text: showsDate ? info.timeLabel : info.clockLabel, color: tint)
                            if info.isCancelled { StedeTagPill(text: "abgesagt", color: StedeTheme.harborRed) }
                            else if isPast { StedeTagPill(text: "vorbei", color: StedeTheme.mudflat) }
                            if info.helpersNeeded > 0 {
                                StedeTagPill(text: helperCount >= info.helpersNeeded ? "Helfer komplett" : "Helfer \(helperCount)/\(info.helpersNeeded)", color: helperCount >= info.helpersNeeded ? StedeTheme.duneGreen : StedeTheme.heather)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                if !info.isPublic {
                    Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                        .accessibilityLabel("Nur für Mitglieder")
                }
            }
            // Karte: Ort linksbündig direkt unter der Kopfzeile, grau, einzeilig — wie bei den Stadt-Terminen.
            if compact, let location = info.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            if !info.description.isEmpty {
                Text(info.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(compact ? 4 : nil)
            }
            if !compact {
                Label { Text(info.longTimeLabel) } icon: { Image(systemName: "clock").foregroundStyle(tint) }.font(.caption)
                Label { Text(info.community) } icon: { Image(systemName: "person.3.fill").foregroundStyle(tint) }.font(.caption)
            }
            if !compact, let location = info.location, !location.isEmpty {
                Label { Text(location) } icon: { Image(systemName: "mappin.and.ellipse").foregroundStyle(tint) }.font(.caption)
            }
            if !info.isCancelled && !isPast {
                if isSignedIn {
                    ParticipationRow(
                        participation: participation,
                        showsHelper: info.helpersNeeded > 0 && (helpersOpen || isHelping),
                        openHelperSlots: max(info.helpersNeeded - helperCount, 0),
                        helpersNeeded: info.helpersNeeded,
                        onParticipate: onParticipate
                    )
                } else {
                    Button(action: signIn) {
                        StedeColorChip(title: "Anmelden, um zuzusagen", symbol: "person.crop.circle", color: StedeTheme.ink)
                    }
                    .buttonStyle(StedeCardButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Detailansicht als Sheet: voller Text, Foto, Zusagen — und für Ersteller
/// und Admins die Namen der Zusagen und Helfer.
struct CommunityEventDetailView: View {
    let info: CommunityEventInfo
    let helperCount: Int
    let participation: MyParticipation?
    let isSignedIn: Bool
    let onParticipate: (ParticipationStatus?, Bool) -> Void
    let signIn: () -> Void
    var onEdit: (() -> Void)?
    /// Ersteller, Admins und Owner sehen die Teilnehmerliste.
    let showsParticipants: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var participants: [EventParticipation] = []
    @State private var loadingParticipants = false
    @ScaledMetric(relativeTo: .body) private var imageHeight = 220.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let imageURL = info.imageURL { EventPhoto(url: imageURL, height: imageHeight) }
                        EventBody(info: info, helperCount: helperCount, participation: participation, isSignedIn: isSignedIn,
                                  onParticipate: onParticipate, signIn: signIn, onEdit: onEdit, compact: false)
                            .padding(StedeTheme.cardPadding)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .stedeCard()
        .goingOutline(participation?.status == .going)

                    if showsParticipants {
                        participantSections
                    }
                }
                .padding()
            }
            .background(StedeTheme.sand)
            .navigationTitle("Termin")
            .stedeBar()
            .toolbar {
                if let onEdit {
                    ToolbarItem(placement: .cancellationAction) { Button("Bearbeiten") { onEdit() } }
                }
                ToolbarItem(placement: .primaryAction) {
                    EventShareButton(info: info) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Teilen")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .task(id: "\(info.id)|\(participation?.status.rawValue ?? "")|\(participation?.helping ?? false)") {
                guard showsParticipants else { return }
                loadingParticipants = true
                participants = (try? await CommunityClient().participations(eventID: info.id)) ?? []
                loadingParticipants = false
            }
        }
    }

    private var helpers: [EventParticipation] { participants.filter { $0.helping && $0.status != .declined } }
    private var going: [EventParticipation] { participants.filter { $0.status == .going } }
    private var maybe: [EventParticipation] { participants.filter { $0.status == .maybe } }

    @ViewBuilder private var participantSections: some View {
        if info.helpersNeeded > 0 {
            StedeSectionHeader(title: "Helfer \(helpers.count)/\(info.helpersNeeded)", symbol: "hands.sparkles.fill")
            if helpers.isEmpty {
                InfoCard { Text(loadingParticipants ? "Lade …" : "Noch niemand eingetragen.").foregroundStyle(.secondary) }
            }
            ForEach(helpers, id: \.userId) { row in personRow(row, color: StedeTheme.heather) }
        }
        StedeSectionHeader(title: "Zusagen \(going.count)" + (maybe.isEmpty ? "" : " · Vielleicht \(maybe.count)"), symbol: "checkmark.circle")
        if going.isEmpty, maybe.isEmpty {
            InfoCard { Text(loadingParticipants ? "Lade …" : "Noch keine Zusagen.").foregroundStyle(.secondary) }
        }
        ForEach(going, id: \.userId) { row in personRow(row, color: StedeTheme.duneGreen) }
        ForEach(maybe, id: \.userId) { row in personRow(row, color: StedeTheme.sunAmber) }
    }

    private func personRow(_ row: EventParticipation, color: Color) -> some View {
        HStack(spacing: 12) {
            PersonAvatar(url: row.profile?.avatarURL, name: row.profile?.displayName ?? "Mitglied", color: color)
            Text(row.profile?.displayName ?? "Mitglied").font(.subheadline.weight(.semibold)).fontDesign(.rounded)
            Spacer()
            if row.helping { StedeTagPill(text: "Helfer", color: StedeTheme.heather) }
            if row.status == .maybe { StedeTagPill(text: "vielleicht", color: StedeTheme.sunAmber) }
        }
        .stedeRowCard()
    }
}

/// Foto oben in der Terminkarte, formatfüllend und an der Kartenkante beschnitten.
struct EventPhoto: View {
    let url: URL
    let height: CGFloat

    var body: some View {
        RemoteImage(url: url) { Rectangle().fill(StedeTheme.seaTeal.opacity(0.12)) }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Eine Zeile gleich breiter Symbol-Chips: Zusage, Vielleicht, Absage und —
/// wenn Helfer gesucht werden — Mithelfen. Nochmal tippen hebt die Wahl auf.
struct ParticipationRow: View {
    let participation: MyParticipation?
    let showsHelper: Bool
    var openHelperSlots = 0
    var helpersNeeded = 0
    let onParticipate: (ParticipationStatus?, Bool) -> Void

    private var status: ParticipationStatus? { participation?.status }
    private var isHelping: Bool { participation?.helping == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Helfer eigens erklärt, nicht als vierter Knopf ohne Kontext.
            if showsHelper { helperBox }
            HStack(spacing: 6) {
                chip(symbol: "checkmark", label: "Ich komme", color: StedeTheme.duneGreen, selected: status == .going) {
                    onParticipate(status == .going ? nil : .going, isHelping && status != .going)
                }
                chip(symbol: "questionmark", label: "Vielleicht", color: StedeTheme.sunAmber, selected: status == .maybe) {
                    onParticipate(status == .maybe ? nil : .maybe, isHelping && status != .maybe)
                }
                chip(symbol: "xmark", label: "Absage", color: StedeTheme.harborRed, selected: status == .declined) {
                    onParticipate(status == .declined ? nil : .declined, false)
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private var helperBox: some View {
        HStack(spacing: 10) {
            Image(systemName: "hands.sparkles.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(StedeTheme.heather)
            VStack(alignment: .leading, spacing: 1) {
                Text(isHelping ? "Du hilfst mit" : "Hier werden Helfer gesucht")
                    .font(.subheadline.weight(.semibold))
                Text(isHelping ? "Danke! Tippe erneut, um dich auszutragen." : slotsText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                if isHelping {
                    onParticipate(status ?? .going, false)
                } else {
                    onParticipate(status == .declined || status == nil ? .going : status, true)
                }
            } label: {
                StedeColorChip(title: isHelping ? "Eingetragen" : "Mithelfen", symbol: isHelping ? "checkmark" : "hand.raised.fill",
                               color: StedeTheme.heather, prominent: isHelping)
            }
            .buttonStyle(StedeCardButtonStyle())
            .accessibilityAddTraits(isHelping ? .isSelected : [])
        }
        .padding(10)
        .background(StedeTheme.heather.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var slotsText: String {
        openHelperSlots == 1 ? "Noch 1 von \(helpersNeeded) Plätzen frei" : "Noch \(openHelperSlots) von \(helpersNeeded) Plätzen frei"
    }

    private func chip(symbol: String, label: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: StedeTheme.chipHeight)
                .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.16)), in: Capsule())
                .foregroundStyle(selected ? Color.white : color)
        }
        .buttonStyle(StedeCardButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// Zugesagte Termine dezent markieren: weiße Karte, feiner grüner Rahmen
    /// im Ton des „Ich komme“-Knopfs statt der vollen Türkis-Fläche.
    func goingOutline(_ isGoing: Bool) -> some View {
        overlay {
            if isGoing {
                StedeTheme.cardShape
                    .strokeBorder(StedeTheme.duneGreen.opacity(0.55), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
    }
}
