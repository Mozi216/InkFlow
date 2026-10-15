import Foundation
import Combine
import UIKit

@MainActor final class Diagnostics: ObservableObject {
    struct Event: Codable {
        var date: Date
        var kind: String
        var values: [String: String]
    }
    @Published private(set) var events: [Event] = []
    func record(_ kind: String, _ values: [String: String] = [:]) {
        events.append(Event(date: Date(), kind: kind, values: values))
        if events.count > 240 { events.removeFirst(events.count - 240) }
    }
    func export() throws -> URL {
        struct Report: Codable {
            var system: String
            var generated: Date
            var note: String
            var events: [Event]
        }
        let report = Report(system: UIDevice.current.systemVersion, generated: Date(),
            note: "Runtime events only. No captured audio, screen images, account tokens, or complete lyrics. Island frame rate requires separate visual measurement.", events: events)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("InkFlow-diagnostics.json")
        try encoder.encode(report).write(to: url, options: .atomic)
        return url
    }
}
