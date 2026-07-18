import Foundation
import Observation

@Observable
@MainActor
final class SyncSaveViewModel {
    enum DeleteLocation: Equatable {
        case device
        case server
        case both
    }

    let romID: Int
    let fileName: String

    var serverStates: [StateSchema] = []
    var serverSaves: [SaveSchema] = []
    var localStates: [SaveStateEntry] = []
    var hasLocalBattery = false
    var localBatteryDate: Date?
    var isLoadingServer = false
    var downloadingStateIds: Set<Int> = []
    var downloadingSaveIds: Set<Int> = []
    var uploadingStateSlots: Set<Int> = []
    var isUploadingBattery = false
    var errorMessage: String?
    var pendingUpload: PendingUpload?
    var screenshotData: [Int: Data] = [:]
    var screenshotFailures: Set<Int> = []
    var operationMessage: String?
    private(set) var selectedSource: GameLaunchSource?
    private var didLoadServerData = false

    private let listSavesUseCase: PListServerSavesUseCase
    private let listStatesUseCase: PListServerStatesUseCase
    private let downloadSaveUseCase: PDownloadSaveUseCase
    private let downloadStateUseCase: PDownloadStateUseCase
    private let uploadSaveUseCase: PUploadSaveUseCase
    private let updateSaveUseCase: PUpdateSaveUseCase
    private let uploadStateUseCase: PUploadStateUseCase
    private let updateStateUseCase: PUpdateStateUseCase
    private let deleteSavesUseCase: PDeleteSavesUseCase
    private let deleteStatesUseCase: PDeleteStatesUseCase
    private let downloadAssetUseCase: PDownloadAssetUseCase
    private let saveStore: PSaveStore
    private let selectionPreference: PGameLaunchSourcePreference

    init(
        romID: Int,
        fileName: String,
        listSavesUseCase: PListServerSavesUseCase,
        listStatesUseCase: PListServerStatesUseCase,
        downloadSaveUseCase: PDownloadSaveUseCase,
        downloadStateUseCase: PDownloadStateUseCase,
        uploadSaveUseCase: PUploadSaveUseCase,
        updateSaveUseCase: PUpdateSaveUseCase,
        uploadStateUseCase: PUploadStateUseCase,
        updateStateUseCase: PUpdateStateUseCase,
        deleteSavesUseCase: PDeleteSavesUseCase,
        deleteStatesUseCase: PDeleteStatesUseCase,
        downloadAssetUseCase: PDownloadAssetUseCase,
        saveStore: PSaveStore,
        selectionPreference: PGameLaunchSourcePreference
    ) {
        self.romID = romID
        self.fileName = fileName
        self.listSavesUseCase = listSavesUseCase
        self.listStatesUseCase = listStatesUseCase
        self.downloadSaveUseCase = downloadSaveUseCase
        self.downloadStateUseCase = downloadStateUseCase
        self.uploadSaveUseCase = uploadSaveUseCase
        self.updateSaveUseCase = updateSaveUseCase
        self.uploadStateUseCase = uploadStateUseCase
        self.updateStateUseCase = updateStateUseCase
        self.deleteSavesUseCase = deleteSavesUseCase
        self.deleteStatesUseCase = deleteStatesUseCase
        self.downloadAssetUseCase = downloadAssetUseCase
        self.saveStore = saveStore
        self.selectionPreference = selectionPreference
        self.selectedSource = selectionPreference.source(for: romID)
    }

    // MARK: - Load

    func loadAll() async {
        isLoadingServer = true
        do {
            async let statesTask = listStatesUseCase.execute(romId: romID)
            async let savesTask = listSavesUseCase.execute(romId: romID)
            let (states, saves) = try await (statesTask, savesTask)
            serverStates = states
            serverSaves = saves
            didLoadServerData = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingServer = false
        localStates = (try? saveStore.listStates(romId: romID)) ?? []
        localBatteryDate = saveStore.batteryModifiedAt(romId: romID)
        hasLocalBattery = localBatteryDate != nil
        validateSelection()
        await loadScreenshots()
    }

    // MARK: - Download

    func downloadServerState(_ state: StateSchema) {
        guard !downloadingStateIds.contains(state.id) else { return }
        if state.missingFromFs {
            errorMessage = "File missing on server — upload it again."
            return
        }
        downloadingStateIds.insert(state.id)
        Task {
            defer { downloadingStateIds.remove(state.id) }
            do {
                let data = try await downloadStateUseCase.execute(id: state.id)
                guard !data.isEmpty else { errorMessage = "Server returned empty file."; return }
                let slot = localSlot(for: state)
                try saveStore.writeState(romId: romID, slot: slot, data: data)
                try saveStore.setStateModifiedAt(romId: romID, slot: slot, date: state.updatedAt)
                if let screenshot = state.screenshot {
                    do {
                        let imageData = try await downloadAssetUseCase.execute(path: screenshot.downloadPath)
                        try saveStore.writeThumbnail(romId: romID, slot: slot, data: imageData)
                        screenshotData[screenshot.id] = imageData
                    } catch {
                        screenshotFailures.insert(screenshot.id)
                        Logger.viewModel.warning("State downloaded without its screenshot: \(error.localizedDescription)")
                    }
                }
                localStates = (try? saveStore.listStates(romId: romID)) ?? []
                setSelection(
                    .state(serverID: state.id, slot: slot, fileName: state.fileName, updatedAt: state.updatedAt, emulator: state.emulator)
                )
                operationMessage = "Downloaded \(state.fileNameNoExt)"
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    func downloadServerSave(_ save: SaveSchema) {
        guard !downloadingSaveIds.contains(save.id) else { return }
        if save.missingFromFs {
            errorMessage = "File missing on server — upload it again."
            return
        }
        downloadingSaveIds.insert(save.id)
        Task {
            defer { downloadingSaveIds.remove(save.id) }
            do {
                let data = try await downloadSaveUseCase.execute(id: save.id)
                guard !data.isEmpty else { errorMessage = "Server returned empty file."; return }
                try saveStore.writeBattery(romId: romID, data: data)
                try saveStore.setBatteryModifiedAt(romId: romID, date: save.updatedAt)
                hasLocalBattery = true
                localBatteryDate = save.updatedAt
                setSelection(
                    .save(serverID: save.id, fileName: save.fileName, updatedAt: save.updatedAt)
                )
                operationMessage = "Downloaded \(save.fileNameNoExt)"
            } catch {
                errorMessage = "Download failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Upload

    func uploadLocalState(entry: SaveStateEntry, targetServerID: Int? = nil) {
        let pending = PendingUpload.state(slot: entry.slot, existingId: targetServerID)
        targetServerID != nil ? (pendingUpload = pending) : executeUpload(pending, update: false)
    }

    func uploadLocalBattery(targetServerID: Int? = nil) {
        let pending = PendingUpload.battery(existingId: targetServerID)
        targetServerID != nil ? (pendingUpload = pending) : executeUpload(pending, update: false)
    }

    func confirmUpload(update: Bool) {
        guard let pending = pendingUpload else { return }
        pendingUpload = nil
        executeUpload(pending, update: update)
    }

    func cancelPendingUpload() { pendingUpload = nil }

    private func executeUpload(_ pending: PendingUpload, update: Bool) {
        switch pending {
        case .state(let slot, let existingId):
            uploadingStateSlots.insert(slot)
            Task {
                defer { uploadingStateSlots.remove(slot) }
                do {
                    guard let data = try saveStore.readState(romId: romID, slot: slot) else { return }
                    let thumbnail = try? saveStore.readThumbnail(romId: romID, slot: slot)
                    let fileName = "slot\(slot).state"
                    let result: StateSchema
                    if update, let existingId {
                        result = try await updateStateUseCase.execute(id: existingId, emulator: nil, fileName: fileName, fileData: data, screenshotData: thumbnail)
                        if let idx = serverStates.firstIndex(where: { $0.id == result.id }) { serverStates[idx] = result }
                    } else {
                        result = try await uploadStateUseCase.execute(romId: romID, emulator: nil, fileName: fileName, fileData: data, screenshotData: thumbnail)
                        serverStates.append(result)
                    }
                    if case .state(let selectedID, let selectedSlot, _, _, _) = selectedSource,
                       selectedSlot == slot, selectedID == nil || selectedID == result.id {
                        setSelection(.state(
                            serverID: result.id,
                            slot: slot,
                            fileName: result.fileName,
                            updatedAt: result.updatedAt,
                            emulator: result.emulator
                        ))
                    }
                    operationMessage = "Uploaded state slot \(slot)"
                } catch {
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        case .battery(let existingId):
            isUploadingBattery = true
            Task {
                defer { isUploadingBattery = false }
                do {
                    guard let data = try saveStore.readBattery(romId: romID) else { return }
                    let fileName = (self.fileName as NSString).deletingPathExtension + ".sav"
                    let result: SaveSchema
                    if update, let existingId {
                        result = try await updateSaveUseCase.execute(id: existingId, emulator: nil, fileName: fileName, fileData: data, screenshotData: nil)
                        if let idx = serverSaves.firstIndex(where: { $0.id == result.id }) { serverSaves[idx] = result }
                    } else {
                        result = try await uploadSaveUseCase.execute(romId: romID, emulator: nil, slot: nil, fileName: fileName, fileData: data, screenshotData: nil)
                        serverSaves.append(result)
                    }
                    if case .save(let selectedID, _, _) = selectedSource,
                       selectedID == nil || selectedID == result.id {
                        setSelection(.save(
                            serverID: result.id,
                            fileName: result.fileName,
                            updatedAt: result.updatedAt
                        ))
                    }
                    operationMessage = "Uploaded battery save"
                } catch {
                    errorMessage = "Upload failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Helpers

    func slotFromFileName(_ name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        guard stem.hasPrefix("slot") else { return nil }
        return Int(stem.dropFirst("slot".count))
    }

    func localSlot(for state: StateSchema) -> Int {
        slotFromFileName(state.fileName) ?? -(state.id + 1)
    }

    func select(_ save: SaveSchema) {
        setSelection(.save(serverID: save.id, fileName: save.fileName, updatedAt: save.updatedAt))
    }

    func select(_ state: StateSchema) {
        setSelection(
            .state(
                serverID: state.id,
                slot: localSlot(for: state),
                fileName: state.fileName,
                updatedAt: state.updatedAt,
                emulator: state.emulator
            )
        )
    }

    func selectLocalBattery() {
        setSelection(
            .save(serverID: nil, fileName: (fileName as NSString).deletingPathExtension + ".sav", updatedAt: localBatteryDate)
        )
    }

    func selectLocalState(_ entry: SaveStateEntry) {
        setSelection(
            .state(serverID: nil, slot: entry.slot, fileName: "slot\(entry.slot).state", updatedAt: entry.modifiedAt, emulator: nil)
        )
    }

    func clearSelection() {
        setSelection(nil)
    }

    func isSelected(_ save: SaveSchema) -> Bool {
        guard case .save(let serverID, _, _) = selectedSource else { return false }
        return serverID == save.id
    }

    func isSelected(_ state: StateSchema) -> Bool {
        guard case .state(let serverID, _, _, _, _) = selectedSource else { return false }
        return serverID == state.id
    }

    func isDownloaded(_ save: SaveSchema) -> Bool {
        guard let localBatteryDate else { return false }
        return abs(localBatteryDate.timeIntervalSince(save.updatedAt)) < 1
    }

    func isDownloaded(_ state: StateSchema) -> Bool {
        let slot = localSlot(for: state)
        guard let localDate = saveStore.stateModifiedAt(romId: romID, slot: slot) else { return false }
        return abs(localDate.timeIntervalSince(state.updatedAt)) < 1
    }

    func delete(_ save: SaveSchema, from location: DeleteLocation) {
        Task {
            do {
                if location == .device || location == .both {
                    try saveStore.deleteBattery(romId: romID)
                    hasLocalBattery = false
                    localBatteryDate = nil
                }
                if location == .server || location == .both {
                    try await deleteSavesUseCase.execute(ids: [save.id])
                    serverSaves.removeAll { $0.id == save.id }
                }
                if isSelected(save) { clearSelection() }
                operationMessage = "Deleted \(save.fileNameNoExt)"
            } catch {
                errorMessage = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    func delete(_ state: StateSchema, from location: DeleteLocation) {
        Task {
            do {
                let slot = localSlot(for: state)
                if location == .device || location == .both {
                    try saveStore.deleteState(romId: romID, slot: slot)
                    localStates.removeAll { $0.slot == slot }
                }
                if location == .server || location == .both {
                    try await deleteStatesUseCase.execute(ids: [state.id])
                    serverStates.removeAll { $0.id == state.id }
                }
                if isSelected(state) { clearSelection() }
                operationMessage = "Deleted \(state.fileNameNoExt)"
            } catch {
                errorMessage = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    func deleteLocalBattery() {
        do {
            try saveStore.deleteBattery(romId: romID)
            hasLocalBattery = false
            localBatteryDate = nil
            if case .save(let serverID, _, _) = selectedSource, serverID == nil {
                clearSelection()
            }
            operationMessage = "Deleted battery save"
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func deleteLocalState(_ entry: SaveStateEntry) {
        do {
            try saveStore.deleteState(romId: romID, slot: entry.slot)
            localStates.removeAll { $0.slot == entry.slot }
            if case .state(let serverID, let slot, _, _, _) = selectedSource,
               serverID == nil, slot == entry.slot {
                clearSelection()
            }
            operationMessage = "Deleted state slot \(entry.slot)"
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func loadScreenshots() async {
        let assets: [(Int, ScreenshotSchema)] =
            serverStates.compactMap { state in state.screenshot.map { ($0.id, $0) } }
            + serverSaves.compactMap { save in save.screenshot.map { ($0.id, $0) } }

        for (id, screenshot) in assets
        where screenshotData[id] == nil && !screenshotFailures.contains(id) {
            do {
                screenshotData[id] = try await downloadAssetUseCase.execute(path: screenshot.downloadPath)
            } catch {
                screenshotFailures.insert(id)
                Logger.viewModel.warning("Failed to load game data screenshot \(id): \(error.localizedDescription)")
            }
        }
    }

    private func validateSelection() {
        guard let selectedSource else { return }
        let exists: Bool
        switch selectedSource {
        case .save(let serverID, _, _):
            if let serverID {
                exists = !didLoadServerData || serverSaves.contains { $0.id == serverID }
            } else {
                exists = hasLocalBattery
            }
        case .state(let serverID, let slot, _, _, _):
            if let serverID {
                exists = !didLoadServerData || serverStates.contains { $0.id == serverID }
            } else {
                exists = localStates.contains { $0.slot == slot }
            }
        }
        if !exists {
            clearSelection()
            operationMessage = "The previously selected save data is no longer available."
        }
    }

    private func setSelection(_ source: GameLaunchSource?) {
        selectedSource = source
        selectionPreference.setSource(source, for: romID)
    }
}
