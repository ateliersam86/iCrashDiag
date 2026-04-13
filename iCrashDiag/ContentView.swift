import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings

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
                ToolbarItem(placement: .automatic) {
                    Button {
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .help("Open Settings (⌘,)")
                }

                if viewModel.analysisReport != nil {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectedCrashID = nil
                            }
                        } label: {
                            Label("Overview", systemImage: "chart.bar.doc.horizontal")
                        }
                        .help("Show overview report")
                    }

                    ToolbarItemGroup(placement: .primaryAction) {
                        let isPro = viewModel.licenseService.isPro
                        Menu {
                            Button {
                                viewModel.copyReportToClipboard()
                            } label: {
                                Label(
                                    isPro ? "Copy as Markdown" : "Copy as Markdown (Pro)",
                                    systemImage: isPro ? "doc.on.clipboard" : "lock.fill"
                                )
                            }

                            Button {
                                viewModel.saveReportAsFile()
                            } label: {
                                Label(
                                    isPro ? "Save as Markdown…" : "Save as Markdown… (Pro)",
                                    systemImage: isPro ? "doc.text" : "lock.fill"
                                )
                            }

                            Divider()

                            Button {
                                viewModel.exportPDF()
                            } label: {
                                Label(
                                    isPro ? "Export PDF…" : "Export PDF… (Pro)",
                                    systemImage: isPro ? "doc.richtext" : "lock.fill"
                                )
                            }
                        } label: {
                            Label("Export", systemImage: isPro ? "square.and.arrow.up" : "square.and.arrow.up.trianglebadge.exclamationmark")
                        }
                        .help(isPro ? "Export report" : "Export report — requires Pro")

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
                    stage: viewModel.loadingStage,
                    progress: viewModel.loadingProgress,
                    parsed: viewModel.loadingParsed,
                    total: viewModel.loadingTotal,
                    currentFile: viewModel.loadingCurrentFile,
                    message: viewModel.loadingMessage
                )
                .ignoresSafeArea()
                .zIndex(100)
                .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }

            // License gate overlay
            if viewModel.showLicenseGate {
                LicenseGateView()
                    .ignoresSafeArea()
                    .zIndex(200)
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.isLoading)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if url.hasDirectoryPath {
                            await viewModel.importFolder(url: url)
                            viewModel.startWatching(folder: url)
                        } else if url.pathExtension.lowercased() == "ips" {
                            await viewModel.importSingleIPS(url: url)
                        }
                    }
                }
            }
            return true
        }
    }
}
