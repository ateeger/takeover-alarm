import Foundation
import SwiftUI
import AlarmKit

struct TakeoverMetadata: AlarmMetadata {}

enum RepeatRule: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly, monthly, yearly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:    return "Never"
        case .daily:   return "Every day"
        case .weekly:  return "Every week"
        case .monthly: return "Every month"
        case .yearly:  return "Every year"
        }
    }
}

struct EventAlarm: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var offset: TimeInterval
    var message: String
}

struct Event: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var start: Date = Date()
    var durationMinutes: Int = 60
    var location: String = ""
    var notes: String = ""
    var repeatRule: RepeatRule = .none
    var alarms: [EventAlarm] = []
}

@MainActor
final class EventStore: ObservableObject {
    @Published var events: [Event] = []
    @Published var lastSyncMessage: String = ""

    private let eventsKey = "takeover.events.v1"
    private let alarmIDsKey = "takeover.alarmIDs.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: eventsKey),
           let decoded = try? JSONDecoder().decode([Event].self, from: data) {
            events = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
    }

    func upsert(_ event: Event) {
        if let i = events.firstIndex(where: { $0.id == event.id }) {
            events[i] = event
        } else {
            events.append(event)
        }
        events.sort { $0.start < $1.start }
        save()
    }

    func delete(_ event: Event) {
        events.removeAll { $0.id == event.id }
        save()
    }

    func occurrences(of event: Event, limit: Int = 4) -> [Date] {
        if event.repeatRule == .none { return [event.start] }

        let cal = Calendar.current
        var out: [Date] = []
        var d = event.start
        let horizon = Date().addingTimeInterval(120 * 24 * 60 * 60)
        var safety = 0

        while out.count < limit && d < horizon && safety < 2000 {
            safety += 1
            if d > Date() { out.append(d) }
            guard let next = nextDate(after: d, rule: event.repeatRule, cal: cal) else { break }
            d = next
        }
        return out
    }

    private func nextDate(after date: Date, rule: RepeatRule, cal: Calendar) -> Date? {
        switch rule {
        case .none:    return nil
        case .daily:   return cal.date(byAdding: .day, value: 1, to: date)
        case .weekly:  return cal.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return cal.date(byAdding: .month, value: 1, to: date)
        case .yearly:  return cal.date(byAdding: .year, value: 1, to: date)
        }
    }

    func syncAlarms() async {
        let saved = UserDefaults.standard.stringArray(forKey: alarmIDsKey) ?? []
        for s in saved {
            if let id = UUID(uuidString: s) {
                try? await AlarmManager.shared.cancel(id: id)
            }
        }
        UserDefaults.standard.set([String](), forKey: alarmIDsKey)

        guard await Self.ensurePermission() else {
            lastSyncMessage = "Alarm permission not granted"
            return
        }

        var newIDs: [String] = []
        var count = 0
        var failure = ""

        for event in events {
            for occurrence in occurrences(of: event) {
                for alarm in event.alarms {
                    if count >= 30 { continue }
                    let fireDate = occurrence.addingTimeInterval(-alarm.offset)
                    if fireDate <= Date() { continue }

                    let id = UUID()
                    do {
                        try await Self.schedule(id: id, at: fireDate, message: alarm.message)
                        newIDs.append(id.uuidString)
                        count += 1
                    } catch {
                        failure = "Error: \(error.localizedDescription)"
                    }
                }
            }
        }

        UserDefaults.standard.set(newIDs, forKey: alarmIDsKey)
        lastSyncMessage = failure.isEmpty
            ? "\(count) alarm\(count == 1 ? "" : "s") scheduled"
            : failure
    }

    static func ensurePermission() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await AlarmManager.shared.requestAuthorization() == .authorized
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    static func schedule(id: UUID, at date: Date, message: String) async throws {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: message),
            stopButton: AlarmButton(
                text: "Stop",
                textColor: .white,
                systemImageName: "stop.fill"
            )
        )

        let attributes = AlarmAttributes<TakeoverMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .red
        )

        _ = try await AlarmManager.shared.schedule(
            id: id,
            configuration: .alarm(schedule: .fixed(date), attributes: attributes)
        )
    }

    func exportText() -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        var lines: [String] = []
        for e in events {
            lines.append("EVENT: \(e.title)")
            lines.append("Start: \(df.string(from: e.start))")
            lines.append("Duration: \(e.durationMinutes) minutes")
            if !e.location.isEmpty { lines.append("Location: \(e.location)") }
            if !e.notes.isEmpty { lines.append("Notes: \(e.notes)") }
            lines.append("Repeats: \(e.repeatRule.label)")
            for a in e.alarms {
                let when = e.start.addingTimeInterval(-a.offset)
                lines.append("Alarm: \(df.string(from: when)) - \(a.message)")
            }
            lines.append("")
        }
        return lines.isEmpty ? "No events." : lines.joined(separator: "\n")
    }
}
