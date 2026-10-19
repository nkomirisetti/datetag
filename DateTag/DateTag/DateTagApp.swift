import SwiftUI

@main
struct DateTagApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
