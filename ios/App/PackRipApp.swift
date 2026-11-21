import SwiftUI

@main
struct PackRipApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var data = DataStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .environmentObject(data)
                .task { data.load() }
        }
    }
}
