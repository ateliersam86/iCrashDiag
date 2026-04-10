import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView()
            } content: {
                CrashListView()
            } detail: {
                if let crash = viewModel.selectedCrash {
                    CrashDetailView(crash: crash)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .id(crash.id)
                } else if let report = viewModel.analysisReport {
                    OverviewView(report: report)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    WelcomeView()
                        .transition(.opacity)
                }
            }
            .navigationSplitViewStyle(.balanced)
            .navigationTitle("iCrashDiag")
            .toolbar {
                if viewModel.analysisReport != nil {
                    ToolbarItem {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectedCrashID = nil
                            }
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

            // Loading overlay — sits on top of everything
            if viewModel.isLoading {
                LoadingView(
                    progress: viewModel.loadingProgress,
                    parsed: viewModel.loadingParsed,
                    total: viewModel.loadingTotal,
                    currentFile: viewModel.loadingCurrentFile
                )
                .ignoresSafeArea()
                .zIndex(100)
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isLoading)
    }
}
