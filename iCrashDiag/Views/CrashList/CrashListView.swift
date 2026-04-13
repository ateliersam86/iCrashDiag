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
                    description: Text("Import a folder or pull from an iPhone.", bundle: .module)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                VStack(spacing: 0) {
                    // Quick filter chips
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

                    // Pro upsell banner when locked crashes exist
                    if viewModel.lockedCount > 0 && !viewModel.licenseService.isPro {
                        LockedCrashesBanner(lockedCount: viewModel.lockedCount) {
                            viewModel.showLicenseGate = true
                        }
                        Divider()
                    }

                    List(viewModel.filteredCrashLogs, selection: $vm.selectedCrashID) { crash in
                        let locked = viewModel.isLocked(crash)
                        CrashRowView(crash: crash, isLocked: locked)
                            .tag(crash.id)
                            .onTapGesture {
                                if locked {
                                    viewModel.showLicenseGate = true
                                } else {
                                    vm.selectedCrashID = crash.id
                                }
                            }
                            .listRowBackground(
                                locked ? Color.primary.opacity(0.02) : Color.clear
                            )
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

// MARK: - Locked crashes banner

private struct LockedCrashesBanner: View {
    let lockedCount: Int
    let onUpgrade: () -> Void

    var body: some View {
        Button(action: onUpgrade) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(lockedCount) crashes hidden")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Upgrade to Pro to see all results", bundle: .module)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Unlock Pro →", bundle: .module)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.04))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quick Filter Chip

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
