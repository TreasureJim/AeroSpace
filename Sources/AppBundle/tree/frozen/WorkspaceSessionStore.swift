import Foundation

private let workspaceSessionWriter = WorkspaceSessionWriter()

private actor WorkspaceSessionWriter {
    private var latestGeneration: UInt64 = 0

    func write(_ data: Data, generation: UInt64, to url: URL) {
        guard generation >= latestGeneration else { return }
        latestGeneration = generation
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("AeroSpace: couldn't save workspace session: \(error)")
        }
    }
}

@MainActor
private enum WorkspaceSessionStore {
    static let url = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)
        .first!
        .appending(path: "AeroSpace/session-state.plist")

    static func load() -> FrozenWorld? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try PropertyListDecoder().decode(FrozenWorld.self, from: data)
        } catch {
            NSLog("AeroSpace: ignoring invalid workspace session: \(error)")
            return nil
        }
    }

    static func save(_ world: FrozenWorld, generation: UInt64) {
        do {
            let data = try PropertyListEncoder().encode(world)
            Task {
                await workspaceSessionWriter.write(data, generation: generation, to: url)
            }
        } catch {
            NSLog("AeroSpace: couldn't encode workspace session: \(error)")
        }
    }
}

@MainActor
private var workspaceSessionPersistenceTask: Task<Void, Never>?

@MainActor
private var workspaceSessionGeneration: UInt64 = 0

@MainActor
func scheduleWorkspaceSessionPersistence() {
    guard TrayMenuModel.shared.isEnabled, !isStartup else { return }
    workspaceSessionPersistenceTask?.cancel()
    workspaceSessionGeneration += 1
    let generation = workspaceSessionGeneration
    workspaceSessionPersistenceTask = Task { @MainActor in
        do {
            try await Task.sleep(for: .seconds(1))
            try Task.checkCancellation()
            WorkspaceSessionStore.save(FrozenWorld(
                workspaces: Workspace.all.map(FrozenWorkspace.init),
                monitors: monitorInfos.map(FrozenMonitor.init),
                windowIds: Workspace.all.flatMap { collectAllWindowIdsRecursive($0) }.toSet(),
            ), generation: generation)
        } catch {
            // A subsequent mutation cancels the pending save.
        }
    }
}

@MainActor
func flushWorkspaceSessionPersistence() {
    workspaceSessionPersistenceTask?.cancel()
    workspaceSessionPersistenceTask = nil
    guard TrayMenuModel.shared.isEnabled else { return }
    workspaceSessionGeneration += 1
    WorkspaceSessionStore.save(FrozenWorld(
        workspaces: Workspace.all.map(FrozenWorkspace.init),
        monitors: monitorInfos.map(FrozenMonitor.init),
        windowIds: Workspace.all.flatMap { collectAllWindowIdsRecursive($0) }.toSet(),
    ), generation: workspaceSessionGeneration)
}

@MainActor
func loadWorkspaceSessionIfPresent() {
    guard let world = WorkspaceSessionStore.load() else { return }
    installLoadedWorkspaceSession(world)
}
