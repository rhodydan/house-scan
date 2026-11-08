import SwiftUI

@main
struct HouseScanApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            ProjectsView()
                .environment(store)
                .task { Exports.clearOldFiles() }
        }
    }
}
