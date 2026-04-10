import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            CrashListView()
        } detail: {
            if let crash = viewModel.selectedCrash {
                CrashDetailView(crash: crash)
            } else if let report = viewModel.analysisReport {
                OverviewView(report: report)
            } else {
                ContentUnavailableView(
                    "iCrashDiag",
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
                    description: Text("Import crash logs to begin diagnosis")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("iCrashDiag")
        .toolbar {
            if viewModel.analysisReport != nil {
                ToolbarItem {
                    Button {
                        viewModel.selectedCrashID = nil
                    } label: {
                        Label("Overview", systemImage: "chart.bar.doc.horizontal")
                    }
                    .help("Show overview report")
                }

                ToolbarItem {
                    Text("KB v\(viewModel.knowledgeBase.version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
