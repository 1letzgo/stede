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
    /// Kommentare eingeschaltet (nur interne Termine).
    let commentsEnabled: Bool
    let createdBy: UUID?
    let communityId: UUID?

    init(_ event: CommunityEvent) {
        id = event.id; title = event.title; community = event.communityName; communityLogoURL = event.communityLogoURL
        starts = event.startsAt; ends = event.endsAt; location = event.location; description = event.description
        imageURL = event.imageURL; isPublic = event.isPublic; isCancelled = event.cancelledAt != nil
        helpersNeeded = event.helpersNeeded; createdBy = event.createdBy; communityId = event.communityId
        commentsEnabled = event.commentsEnabled && !event.isPublic
    }

    init(_ event: PublicEvent) {
        id = event.id; title = event.title; community = event.communityName; communityLogoURL = event.communityLogoURL
        starts = event.startsAt; ends = event.endsAt; location = event.location; description = event.description
        imageURL = event.imageURL; isPublic = true; isCancelled = false
        helpersNeeded = event.helpersNeeded; createdBy = nil; communityId = nil
        commentsEnabled = false
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
    /// Kommentare wie bei Umfragen: Knopf unten rechts, öffnet den Verlauf als Sheet.
    var commentCount = 0
    var onComments: (() -> Void)?

    @ScaledMetric(relativeTo: .body) private var imageHeight = 170.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsPhoto, let imageURL = info.imageURL { EventPhoto(url: imageURL, height: imageHeight) }
            VStack(alignment: .leading, spacing: 10) {
                EventBody(info: info, helperCount: helperCount, participation: participation, isSignedIn: isSignedIn,
                          onParticipate: onParticipate, signIn: signIn, onEdit: onEdit, compact: true, showsDate: showsDate)
                if info.commentsEnabled, let onComments {
                    HStack {
                        Spacer(minLength: 0)
                        CommentsButton(count: commentCount, tint: StedeTheme.seaTeal, action: onComments)
                    }
                }
            }
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
                        if let imageURL = info.imageURL { FullEventPhoto(url: imageURL, placeholderHeight: imageHeight) }
                        EventBody(info: info, helperCount: helperCount, participation: participation, isSignedIn: isSignedIn,
                                  onParticipate: onParticipate, signIn: signIn, onEdit: onEdit, compact: false)
                            .padding(StedeTheme.cardPadding)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .stedeCard()
        .goingOutline(participation?.status == .going)

                    if info.commentsEnabled, isSignedIn {
                        EventCommentsSection(eventID: info.id, canModerate: showsParticipants)
                    }

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

/// Beitragsbild in der Detailansicht: volle Breite, Höhe nach Seitenverhältnis — nichts abgeschnitten.
struct FullEventPhoto: View {
    let url: URL
    let placeholderHeight: CGFloat

    var body: some View {
        RemoteImage(url: url, contentMode: .fit) {
            Rectangle().fill(StedeTheme.seaTeal.opacity(0.12)).frame(height: placeholderHeight)
        }
        .frame(maxWidth: .infinity)
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
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(isHelping ? "Danke fürs Mithelfen!" : slotsText)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Button {
                if isHelping {
                    onParticipate(status ?? .going, false)
                } else {
                    onParticipate(status == .declined || status == nil ? .going : status, true)
                }
            } label: {
                // Beide Beschriftungen liegen übereinander, damit der Knopf beim Umschalten gleich groß bleibt.
                HStack(spacing: 6) {
                    Image(systemName: isHelping ? "checkmark" : "hand.raised.fill")
                        .font(.caption.weight(.bold))
                        .frame(width: 16)
                    ZStack {
                        Text("Eingetragen").opacity(isHelping ? 1 : 0)
                        Text("Mithelfen").opacity(isHelping ? 0 : 1)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .fontDesign(.rounded)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minHeight: StedeTheme.chipHeight)
                .background(isHelping ? AnyShapeStyle(StedeTheme.heather) : AnyShapeStyle(StedeTheme.heather.opacity(0.16)), in: Capsule())
                .foregroundStyle(isHelping ? Color.white : StedeTheme.heather)
                .fixedSize()
            }
            .buttonStyle(StedeCardButtonStyle())
            .accessibilityLabel(isHelping ? "Eingetragen, austragen" : "Mithelfen")
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

/// Kommentare unter einem internen Termin: Liste plus Eingabezeile. Löschen per langem
/// Druck — eigene Kommentare immer, fremde nur für Ersteller und Admins (RLS prüft mit).
/// Wessen Kommentare: ein interner Termin oder eine Umfrage.
enum CommentTarget: Hashable {
    case event(UUID)
    case poll(UUID)
}

struct EventCommentsSection: View {
    let target: CommentTarget
    let canModerate: Bool

    init(eventID: UUID, canModerate: Bool) {
        self.target = .event(eventID)
        self.canModerate = canModerate
    }

    init(target: CommentTarget, canModerate: Bool) {
        self.target = target
        self.canModerate = canModerate
    }

    @Environment(AuthStore.self) private var auth
    @State private var comments: [EventComment] = []
    @State private var draft = ""
    @State private var sending = false
    @State private var loading = true
    @State private var failed = false
    private let client = CommunityClient()
    private let polls = PollClient()

    private static let timeFormat = Date.FormatStyle(locale: IslandTime.germanLocale, timeZone: IslandTime.timeZone)
        .day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    var body: some View {
        VStack(alignment: .leading, spacing: StedeTheme.cardSpacing) {
            StedeSectionHeader(title: comments.isEmpty ? "Kommentare" : "Kommentare \(comments.count)", symbol: "bubble.left.and.bubble.right.fill")
            if comments.isEmpty {
                InfoCard {
                    Text(loading ? "Lade …" : "Noch keine Kommentare – schreib den ersten.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(comments) { comment in
                commentRow(comment)
            }
            HStack(spacing: 8) {
                TextField("Kommentar schreiben", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StedeTheme.sand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: sending ? "ellipsis" : "paperplane.fill")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 40, height: 40)
                        .background(canSend ? AnyShapeStyle(StedeTheme.seaTeal) : AnyShapeStyle(StedeTheme.seaTeal.opacity(0.3)), in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(StedeCardButtonStyle())
                .disabled(!canSend)
                .accessibilityLabel("Senden")
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .stedeCard()
            if failed {
                Text("Das hat nicht geklappt. Bitte versuche es noch einmal.")
                    .font(.footnote).foregroundStyle(StedeTheme.harborRed)
            }
        }
        .task(id: target) { await load() }
    }

    private var canSend: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending }

    private func commentRow(_ comment: EventComment) -> some View {
        let name = comment.profile?.displayName ?? "Mitglied"
        return HStack(alignment: .top, spacing: 12) {
            PersonAvatar(url: comment.profile?.avatarURL, name: name, side: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(.subheadline.weight(.semibold)).fontDesign(.rounded)
                    Spacer(minLength: 8)
                    Text(comment.createdAt.formatted(Self.timeFormat)).font(.caption).foregroundStyle(.secondary)
                }
                Text(comment.body).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .stedeRowCard()
        .contextMenu {
            if comment.userId == auth.userID || canModerate {
                Button("Kommentar löschen", systemImage: "trash", role: .destructive) {
                    Task { await delete(comment) }
                }
            }
        }
    }

    private func load() async {
        loading = true
        switch target {
        case let .event(id): comments = (try? await client.comments(eventID: id)) ?? comments
        case let .poll(id): comments = (try? await polls.comments(pollID: id)) ?? comments
        }
        loading = false
    }

    private func send() async {
        guard let userID = auth.userID else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        failed = false
        do {
            switch target {
            case let .event(id): try await client.addComment(eventID: id, userID: userID, body: String(text.prefix(1000)))
            case let .poll(id): try await polls.addComment(pollID: id, userID: userID, body: String(text.prefix(1000)))
            }
            draft = ""
            await load()
        } catch {
            failed = true
        }
        sending = false
    }

    private func delete(_ comment: EventComment) async {
        do {
            switch target {
            case .event: try await client.deleteComment(id: comment.id)
            case .poll: try await polls.deleteComment(id: comment.id)
            }
            withAnimation { comments.removeAll { $0.id == comment.id } }
        } catch {
            failed = true
        }
    }
}
