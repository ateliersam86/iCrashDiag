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
                VStack(spacing: 0) {
                    if !viewModel.crashLogs.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(QuickFilter.allCases) { filter in
                                    QuickFilterChip(
                                        filter: filter,
                                        isSelected: viewModel.quickFilter == filter,
                                        count: countFor(filter)
                                    ) {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            vm.quickFilter = filter
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        Divider()
                    }

                    List(viewModel.filteredCrashLogs, selection: $vm.selectedCrashID) { crash in
                        CrashRowView(crash: crash)
                            .tag(crash.id)
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.filteredCrashLogs.map(\.id))
                    .searchable(text: $vm.searchText, prompt: "Search crashes...")
                }
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

    private func countFor(_ filter: QuickFilter) -> Int {
        switch filter {
        case .all: return viewModel.crashLogs.count
        case .hardware: return viewModel.crashLogs.filter { $0.diagnosis?.severity == .hardware }.count
        case .critical: return viewModel.crashLogs.filter { $0.diagnosis?.severity == .critical }.count
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            return viewModel.crashLogs.filter { $0.timestamp >= start }.count
        case .reboots: return viewModel.rebootCount
        }
    }
}

private struct QuickFilterChip: View {
    let filter: QuickFilter
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                Text(filter.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                if count > 0 && filter != .all {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? filter.color : .secondary)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(isSelected ? filter.color : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected ? filter.color.opacity(0.12) : Color.primary.opacity(0.04),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? filter.color.opacity(0.35) : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}
