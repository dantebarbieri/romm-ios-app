import SwiftUI
import UIKit

struct RomGameDataSection: View {
    enum DataType: String, CaseIterable {
        case states = "States"
        case saves = "Saves"
    }

    private enum PendingDelete: Identifiable {
        case save(SaveSchema)
        case state(StateSchema)
        case localBattery
        case localState(SaveStateEntry)

        var id: String {
            switch self {
            case .save(let save): return "save-\(save.id)"
            case .state(let state): return "state-\(state.id)"
            case .localBattery: return "local-battery"
            case .localState(let entry): return "local-state-\(entry.slot)"
            }
        }
    }

    let viewModel: SyncSaveViewModel
    let onPlay: () -> Void

    @State private var selectedType: DataType = .states
    @State private var pendingDelete: PendingDelete?
    @AppStorage("cloud_save_sync_enabled") private var cloudSyncEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            syncStatus

            Picker("Game data type", selection: $selectedType) {
                ForEach(DataType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.isLoadingServer {
                ProgressView("Loading game data...")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else {
                selectedContent
            }

            if viewModel.selectedSource != nil {
                Button("Start Normally", systemImage: "arrow.counterclockwise") {
                    viewModel.clearSelection()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            if let message = viewModel.operationMessage {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
        .alert(
            "Game Data Error",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete Save Data",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            deleteButtons
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Choose where this save data should be removed. Deleting the selected item returns Play to normal launch.")
        }
    }

    private var syncStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: cloudSyncEnabled ? "icloud.fill" : "icloud.slash")
            VStack(alignment: .leading, spacing: 2) {
                Text(cloudSyncEnabled ? "Cloud Save Sync On" : "Cloud Save Sync Off")
                    .font(.subheadline.weight(.semibold))
                Text(cloudSyncEnabled ? "Automatic sync runs around emulator sessions." : "Use the controls below to transfer data manually.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedType {
        case .states:
            if viewModel.serverStates.isEmpty && viewModel.localStates.isEmpty {
                emptyView(title: "No states available", icon: "gamecontroller")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.serverStates) { state in
                        StateSelectionCard(
                            state: state,
                            imageData: state.screenshot.flatMap { viewModel.screenshotData[$0.id] },
                            isSelected: viewModel.isSelected(state),
                            isDownloaded: viewModel.isDownloaded(state),
                            isBusy: viewModel.downloadingStateIds.contains(state.id),
                            onSelect: { viewModel.select(state) },
                            onPrimaryAction: {
                                if viewModel.isDownloaded(state) {
                                    viewModel.select(state)
                                    onPlay()
                                } else {
                                    viewModel.downloadServerState(state)
                                }
                            },
                            onUpload: localEntry(for: state).map { entry in
                                { viewModel.uploadLocalState(entry: entry, targetServerID: state.id) }
                            },
                            onDelete: { pendingDelete = .state(state) }
                        )
                    }
                    ForEach(unmatchedLocalStates) { entry in
                        LocalGameDataCard(
                            title: "Slot \(entry.slot)",
                            date: entry.modifiedAt,
                            icon: "bookmark.fill",
                            isSelected: isSelected(entry),
                            onSelect: { viewModel.selectLocalState(entry) },
                            onPlay: {
                                viewModel.selectLocalState(entry)
                                onPlay()
                            },
                            onUpload: { viewModel.uploadLocalState(entry: entry) },
                            onDelete: { pendingDelete = .localState(entry) }
                        )
                    }
                }
            }
        case .saves:
            if viewModel.serverSaves.isEmpty && !viewModel.hasLocalBattery {
                emptyView(title: "No saves available", icon: "memorychip")
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.serverSaves) { save in
                        SaveSelectionCard(
                            save: save,
                            imageData: save.screenshot.flatMap { viewModel.screenshotData[$0.id] },
                            isSelected: viewModel.isSelected(save),
                            isDownloaded: viewModel.isDownloaded(save),
                            isBusy: viewModel.downloadingSaveIds.contains(save.id),
                            onSelect: { viewModel.select(save) },
                            onPrimaryAction: {
                                if viewModel.isDownloaded(save) {
                                    viewModel.select(save)
                                    onPlay()
                                } else {
                                    viewModel.downloadServerSave(save)
                                }
                            },
                            onUpload: viewModel.hasLocalBattery
                                ? { viewModel.uploadLocalBattery(targetServerID: save.id) }
                                : nil,
                            onDelete: { pendingDelete = .save(save) }
                        )
                    }
                    if viewModel.hasLocalBattery && !hasMatchedServerBattery {
                        LocalGameDataCard(
                            title: "Battery save",
                            date: viewModel.localBatteryDate,
                            icon: "memorychip",
                            isSelected: isLocalBatterySelected,
                            onSelect: viewModel.selectLocalBattery,
                            onPlay: {
                                viewModel.selectLocalBattery()
                                onPlay()
                            },
                            onUpload: { viewModel.uploadLocalBattery() },
                            onDelete: { pendingDelete = .localBattery }
                        )
                    }
                }
            }
        }
    }

    private var unmatchedLocalStates: [SaveStateEntry] {
        viewModel.localStates.filter { entry in
            !viewModel.serverStates.contains { viewModel.localSlot(for: $0) == entry.slot }
        }
    }

    private func localEntry(for state: StateSchema) -> SaveStateEntry? {
        let slot = viewModel.localSlot(for: state)
        return viewModel.localStates.first { $0.slot == slot }
    }

    private var hasMatchedServerBattery: Bool {
        viewModel.serverSaves.contains(where: viewModel.isDownloaded)
    }

    private var isLocalBatterySelected: Bool {
        guard case .save(let serverID, _, _) = viewModel.selectedSource else { return false }
        return serverID == nil
    }

    private func isSelected(_ entry: SaveStateEntry) -> Bool {
        guard case .state(let serverID, let slot, _, _, _) = viewModel.selectedSource else { return false }
        return serverID == nil && slot == entry.slot
    }

    private func emptyView(title: String, icon: String) -> some View {
        ContentUnavailableView(title, systemImage: icon)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    @ViewBuilder
    private var deleteButtons: some View {
        switch pendingDelete {
        case .save(let save):
            if viewModel.isDownloaded(save) {
                Button("Delete On Device", role: .destructive) {
                    viewModel.delete(save, from: .device)
                    pendingDelete = nil
                }
            }
            Button("Delete On Server", role: .destructive) {
                viewModel.delete(save, from: .server)
                pendingDelete = nil
            }
            if viewModel.isDownloaded(save) {
                Button("Delete Both", role: .destructive) {
                    viewModel.delete(save, from: .both)
                    pendingDelete = nil
                }
            }
        case .state(let state):
            if viewModel.isDownloaded(state) {
                Button("Delete On Device", role: .destructive) {
                    viewModel.delete(state, from: .device)
                    pendingDelete = nil
                }
            }
            Button("Delete On Server", role: .destructive) {
                viewModel.delete(state, from: .server)
                pendingDelete = nil
            }
            if viewModel.isDownloaded(state) {
                Button("Delete Both", role: .destructive) {
                    viewModel.delete(state, from: .both)
                    pendingDelete = nil
                }
            }
        case .localBattery:
            Button("Delete On Device", role: .destructive) {
                viewModel.deleteLocalBattery()
                pendingDelete = nil
            }
        case .localState(let entry):
            Button("Delete On Device", role: .destructive) {
                viewModel.deleteLocalState(entry)
                pendingDelete = nil
            }
        case nil:
            EmptyView()
        }
    }
}

private struct StateSelectionCard: View {
    let state: StateSchema
    let imageData: Data?
    let isSelected: Bool
    let isDownloaded: Bool
    let isBusy: Bool
    let onSelect: () -> Void
    let onPrimaryAction: () -> Void
    let onUpload: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        GameDataSelectionCard(
            title: state.fileNameNoExt,
            emulator: state.emulator,
            size: state.fileSizeBytes,
            date: state.updatedAt,
            imageData: imageData,
            placeholderIcon: "gamecontroller.fill",
            isSelected: isSelected,
            isDownloaded: isDownloaded,
            isBusy: isBusy,
            playTitle: "Load State",
            onSelect: onSelect,
            onPrimaryAction: onPrimaryAction,
            onUpload: onUpload,
            onDelete: onDelete
        )
    }
}

private struct SaveSelectionCard: View {
    let save: SaveSchema
    let imageData: Data?
    let isSelected: Bool
    let isDownloaded: Bool
    let isBusy: Bool
    let onSelect: () -> Void
    let onPrimaryAction: () -> Void
    let onUpload: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        GameDataSelectionCard(
            title: save.fileNameNoExt,
            emulator: save.emulator,
            size: save.fileSizeBytes,
            date: save.updatedAt,
            imageData: imageData,
            placeholderIcon: "memorychip",
            isSelected: isSelected,
            isDownloaded: isDownloaded,
            isBusy: isBusy,
            playTitle: "Play with Save",
            onSelect: onSelect,
            onPrimaryAction: onPrimaryAction,
            onUpload: onUpload,
            onDelete: onDelete
        )
    }
}

private struct GameDataSelectionCard: View {
    let title: String
    let emulator: String?
    let size: Int
    let date: Date
    let imageData: Data?
    let placeholderIcon: String
    let isSelected: Bool
    let isDownloaded: Bool
    let isBusy: Bool
    let playTitle: String
    let onSelect: () -> Void
    let onPrimaryAction: () -> Void
    let onUpload: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 10) {
                    preview
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title)
                                .font(.headline)
                                .lineLimit(1)
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.tint)
                        }
                    }
                    HStack(spacing: 6) {
                        if let emulator {
                            Text(emulator)
                        }
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                        Label(isDownloaded ? "On Device" : "On Server", systemImage: isDownloaded ? "iphone" : "icloud")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint("Select as the launch source")

            Divider()

            HStack {
                Button(action: onPrimaryAction) {
                    if isBusy {
                        ProgressView()
                    } else {
                        Label(isDownloaded ? playTitle : "Download", systemImage: isDownloaded ? "play.fill" : "arrow.down.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Spacer()

                Menu {
                    if let onUpload {
                        Button("Upload", systemImage: "arrow.up.circle", action: onUpload)
                    }
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .accessibilityLabel("More actions")
            }
            .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 3 : 1)
        }
        .contextMenu {
            Button(isDownloaded ? playTitle : "Download", action: onPrimaryAction)
            if let onUpload {
                Button("Upload", systemImage: "arrow.up.circle", action: onUpload)
            }
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.secondary.opacity(0.12))
                .frame(height: 160)
                .overlay {
                    Image(systemName: placeholderIcon)
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct LocalGameDataCard: View {
    let title: String
    let date: Date?
    let icon: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onUpload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.headline)
                        if let date {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.tint)
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Divider()
            HStack {
                Button("Play", systemImage: "play.fill", action: onPlay)
                    .buttonStyle(.borderedProminent)
                Button("Upload", systemImage: "icloud.and.arrow.up", action: onUpload)
                    .buttonStyle(.bordered)
                Spacer()
                Menu {
                    Button("Delete from Device", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
            }
            .padding(12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 3 : 1)
        }
        .contextMenu {
            Button("Play", systemImage: "play.fill", action: onPlay)
            Button("Upload", systemImage: "icloud.and.arrow.up", action: onUpload)
            Button("Delete from Device", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}
