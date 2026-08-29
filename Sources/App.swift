import SwiftUI
import AlarmKit

struct TakeoverMetadata: AlarmMetadata {}

@main
struct TakeoverAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    private let manager = AlarmManager.shared
    @State private var status = "Tap to test"

    var body: some View {
        VStack(spacing: 24) {
            Text("Takeover")
                .font(.largeTitle)
                .bold()

            Text(status)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Ring in 30 seconds") {
                Task { await scheduleTest() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func requestPermission() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await manager.requestAuthorization() == .authorized
            } catch {
                return false
            }
        @unknown default:
            return false
        }
    }

    private func scheduleTest() async {
        guard await requestPermission() else {
            status = "Permission denied"
            return
        }

        let alert = AlarmPresentation.Alert(
            title: "TEE TIME 10 AM, DON'T FORGET",
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

        do {
            _ = try await manager.schedule(
                id: UUID(),
                configuration: .timer(duration: 30, attributes: attributes)
            )
            status = "Alarm set. Lock your phone and wait."
        } catch {
            status = "Error: \(error)"
        }
    }
}
