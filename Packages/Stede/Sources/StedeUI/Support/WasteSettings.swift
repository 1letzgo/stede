import StedeCore
import SwiftUI

/// Gemerkte Straße für den Abfuhrkalender — liegt in den UserDefaults, damit
/// Start und Abfuhr-Ansicht denselben Stand sehen.
struct WasteSettings {
    @AppStorage("waste.street") var streetID: Int = 0
    @AppStorage("waste.section") var sectionID: Int = 0
    @AppStorage("waste.branchSection") var branchSectionID: Int = 0

    var street: WasteStreet? {
        streetID == 0 ? nil : WasteStreetStore.directory.street(id: streetID)
    }

    /// Erst vollständig, wenn alle nötigen Abschnitte gewählt sind.
    var selection: WasteSelection? {
        guard let street else { return nil }
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
