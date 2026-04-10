import SwiftUI

struct CrashListView: View {
    @Environment(AppViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel

        List(viewModel.filteredCrashLogs, selection: $vm.selectedCrashID) { crash in
            CrashRowView(crash: crash)
                .tag(crash.id)
        }
        .searchable(text: $vm.searchText, prompt: "Search crashes...")
        .toolbar {
            ToolbarItem {
                Picker("Sort", selection: $vm.sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .overlay {
            if viewModel.crashLogs.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Crash Logs",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Import a folder or pull from an iPhone to get started.")
                )
            }
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView(value: viewModel.loadingProgress)
                        .frame(width: 200)
                    Text(viewModel.loadingMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
