import Foundation
import Testing
@testable import StedeCore

/// „Meine Aufgaben“ liegt im `CommunityCache` in der flachen Form der Abfrage — muss sich selbst wieder lesen.
@Test func assignedTaskRoundTripsThroughCache() throws {
    let json = """
    {"id":"6f1d2c3a-0000-4000-8000-000000000001","project_id":"6f1d2c3a-0000-4000-8000-000000000002",
     "community_id":"6f1d2c3a-0000-4000-8000-000000000003","title":"Stand aufbauen","description":null,
     "status":"in_progress","due_date":"2026-10-03","created_by":null,"created_at":"2026-09-27T10:00:00Z","done_at":null,
     "community_task_assignees":[{"user_id":"6f1d2c3a-0000-4000-8000-000000000004","profiles":null}],
     "community_projects":{"title":"Herbstmarkt","archived_at":null}}
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let task = try decoder.decode(AssignedTask.self, from: Data(json.utf8))
    let cached = try JSONDecoder().decode(AssignedTask.self, from: JSONEncoder().encode(task))
    #expect(cached == task)
    #expect(cached.projectTitle == "Herbstmarkt")
    #expect(!cached.projectArchived)
    #expect(cached.task.status == .inProgress)
    #expect(cached.task.assignees.count == 1)
}

/// Das Gastro-Bundle muss mit Merkmalen lesbar bleiben — sonst stünde „Gastro“ leer da.
@Test func gastroBundleDecodesDeliveryServices() throws {
    let url = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../Sources/StedeCore/Resources/gastronomie.json").standardized
    let directory = try JSONDecoder().decode(GastroDirectory.self, from: Data(contentsOf: url))
    let delivering = directory.places.filter(\.delivers)
    #expect(delivering.count == 6)
    // Nie Links auf Bestellplattformen — nur die eigene Website der Betriebe.
    #expect(!directory.places.contains { ($0.extraLinkURL ?? "").contains("lieferando") || ($0.website ?? "").contains("lieferando") })
}
