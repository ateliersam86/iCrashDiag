import SwiftUI

struct CrashListView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        Group {
            if viewModel.crashLogs.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Crash Logs",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Import a folder or pull from an iPhone.")
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                List(viewModel.filteredCrashLogs, selection: $vm.selectedCrashID) { crash in
                    CrashRowView(crash: crash)
                        .tag(crash.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.filteredCrashLogs.map(\.id))
                .searchable(text: $vm.searchText, prompt: "Search crashes…")
                .toolbar {
                    ToolbarItem {
                        if !viewModel.crashLogs.isEmpty {
                            Text("\(viewModel.filteredCrashLogs.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3), value: viewModel.filteredCrashLogs.count)
                        }
                    }
                    ToolbarItem {
                        Picker("Sort", selection: $vm.sortOrder) {
                            ForEach(SortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.crashLogs.isEmpty)
    }
}
