import StedeCore
import SwiftUI

/// Leitet aus den gemerkten IDs (UserDefaults `waste.*`) Straße und vollständige
/// Auswahl ab. Reine Funktionen — die Views halten die `@AppStorage`-Werte selbst,
/// nur so bekommen sie Änderungen sofort mit.
enum WasteSettings {
    static func street(id: Int) -> WasteStreet? {
        id == 0 ? nil : WasteStreetStore.directory.street(id: id)
    }

    /// Erst vollständig, wenn alle nötigen Abschnitte gewählt sind.
    static func selection(streetID: Int, sectionID: Int, branchSectionID: Int) -> WasteSelection? {
        guard let street = street(id: streetID) else { return nil }
        if street.needsSection, sectionID == 0 { return nil }
        if street.needsBranchSection, branchSectionID == 0 { return nil }
        return WasteSelection(
            streetID: street.id,
            sectionID: street.needsSection ? sectionID : nil,
            branchSectionID: street.needsBranchSection ? branchSectionID : nil
        )
    }
}

/// Farbe je Abfallart — aus der Palette, nicht die Tonnenfarben.
extension WasteKind {
    var tint: Color {
        switch self {
        case .residual: StedeTheme.ink
        case .paper: StedeTheme.seaTeal
        case .yellowBag: StedeTheme.sunAmber
        case .organic: StedeTheme.duneGreen
        case .branches: StedeTheme.mudflat
        case .hazardous: StedeTheme.harborRed
        case .other: StedeTheme.heather
        }
    }
}
