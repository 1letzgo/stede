import Foundation
import Testing
@testable import StedeCore

/// Eine Gemeinde ohne Bahn, Bus und Abfuhr (Loog) lässt deren Felder weg — muss trotzdem lesbar sein,
/// und fehlende Schlüssel in `features` heißen „aus“.
@Test func tenantWithoutTransitDecodesFeatures() throws {
    let json = """
    {"slug":"loog","municipality":"Langeoog","region":"langeoog","center":[53.747,7.483],"bbox":[53.685,7.35,53.805,7.71],
     "features":{"weather":true,"ferry":true,"tides":true,"train":false,"places":["gastro","sights"]}}
    """
    let tenant = try JSONDecoder().decode(TenantConfig.self, from: Data(json.utf8))
    #expect(tenant.stations.isEmpty)
    #expect(tenant.busDefaultStop.isEmpty)
    let features = try #require(tenant.features)
    #expect(features.enabled == [.weather, .ferry, .tides])
    #expect(features.places == ["gastro", "sights"])

    let cached = try JSONDecoder().decode(TenantConfig.self, from: JSONEncoder().encode(tenant))
    #expect(cached == tenant)
}

/// Die Marke begrenzt, was eine Gemeinde einschalten kann.
@Test func brandLimitsTenantFeatures() {
    let tenant = FeatureSet([.weather, .groups, .ferry], places: ["gastro", "playgrounds"])
    let brand = FeatureSet([.weather, .ferry], places: ["gastro"])
    let result = tenant.intersection(brand)
    #expect(result.enabled == [.weather, .ferry])
    #expect(result.places == ["gastro"])
}

/// Der Bundle-Stand kennt jede Gemeinde mit Bausteinen.
/// Ohne `StedeBrand` läuft der Test als stede: Loog ist dann herausgefiltert.
@Test func bundledTenantsCarryFeatures() {
    let list = Tenants.bundled
    #expect(list.count == 6)
    #expect(list.allSatisfy { $0.features != nil && $0.region == "ammerland" })
}
