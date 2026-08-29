import SwiftUI

@main
struct TakeoverAlarmApp: App {
    @StateObject private var store = EventStore()

    var body: some Scene {
        WindowGroup {
            EventListView().environmentObject(store)
        }
    }
}

struct EventListView: View {
    @EnvironmentObject var store: EventStore
    @State private var editing: Event?
    @State private var showExport = false

    var body: some View {
        NavigationStack {
            List {
                if !store.lastSyncMessage.isEmpty {
                    Section {
                        Text(store.lastSyncMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if store.events.isEmpty {
                    Text("No events yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                }

                ForEach(store.events) { event in
                    Button {
                        editing = event
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title.isEmpty ? "Untitled" : event.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(event.start.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !event.alarms.isEmpty {
                                Text("\(event.alarms.count) alarm\(event.alarms.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet { store.delete(store.events[i]) }
                    Task { await store.syncAlarms() }
                }
            }
            .navigationTitle("Takeover")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Export") { showExport = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = Event()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { event in
                EventEditView(event: event).environmentObject(store)
            }
            .sheet(isPresented: $showExport) {
                ExportView(text: store.exportText())
            }
            .task { await store.syncAlarms() }
        }
    }
}

struct EventEditView: View {
    @EnvironmentObject var store: EventStore
    @Environment(\.dismiss) private var dismiss
    @State var event: Event
    @State private var newAlarmDate = Date()
    @State private var newAlarmMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $event.title)
                    DatePicker("Starts", selection: $event.start)
                    Stepper("Duration \(event.durationMinutes) min",
                            value: $event.durationMinutes,
                            in: 5...1440,
                            step: 5)
                    TextField("Location", text: $event.location)
                    Picker("Repeats", selection: $event.repeatRule) {
                        ForEach(RepeatRule.allCases) { rule in
                            Text(rule.label).tag(rule)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $event.notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Alarms") {
                    ForEach(event.alarms) { alarm in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(alarmDate(alarm).formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                            Text(alarm.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        event.alarms.remove(atOffsets: indexSet)
                    }

                    DatePicker("New alarm at", selection: $newAlarmDate)
                    TextField("Message on screen", text: $newAlarmMessage)

                    Button("Add alarm") {
                        let text = newAlarmMessage.isEmpty
                            ? (event.title.isEmpty ? "Reminder" : event.title)
                            : newAlarmMessage
                        let offset = event.start.timeIntervalSince(newAlarmDate)
                        event.alarms.append(EventAlarm(offset: offset, message: text))
                        event.alarms.sort { $0.offset > $1.offset }
                        newAlarmMessage = ""
                    }
                }
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.upsert(event)
                        dismiss()
                        Task { await store.syncAlarms() }
                    }
                }
            }
            .onAppear { newAlarmDate = event.start }
        }
    }

    private func alarmDate(_ alarm: EventAlarm) -> Date {
        event.start.addingTimeInterval(-alarm.offset)
    }
}

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    let text: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding()
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: text) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
