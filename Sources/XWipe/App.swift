import SwiftUI

@main
struct XWipeApp: App {
    @StateObject private var engine = Engine()

    var body: some Scene {
        WindowGroup("XWipe") {
            ContentView()
                .environmentObject(engine)
                .frame(minWidth: 1000, minHeight: 640)
        }
    }
}
