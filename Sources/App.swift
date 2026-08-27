import SwiftUI

@main
struct TakeoverAlarmApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Takeover")
                .font(.largeTitle)
                .bold()
            Text("It works.")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
