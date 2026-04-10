import SwiftUI

@main
struct iCrashDiagApp: App {
    @State private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(viewModel)
                .task {
                    let manager = KnowledgeBaseManager()
                    let _ = await manager.checkForUpdates(currentVersion: viewModel.knowledgeBase.version)
                }
        }
        .defaultSize(width: 1200, height: 750)
    }
}
