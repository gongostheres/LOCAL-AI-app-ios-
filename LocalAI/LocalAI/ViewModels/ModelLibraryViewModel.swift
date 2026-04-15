import Foundation
import Observation

@Observable
final class ModelLibraryViewModel {

    var models: [AIModel] = []
    var downloadProgress: [String: Double] = [:]
    var downloadingIds: Set<String> = []
    var connectingIds: Set<String> = []      // waiting for first byte
    var failedIds: Set<String> = []
    var errorMessage: String?

    private let key = "downloaded_model_ids"

    init() { reload() }

    // MARK: - Computed

    var downloadedModels: [AIModel] { models.filter(\.isDownloaded) }

    var totalDownloadedGB: Double {
        downloadedModels.reduce(0) { $0 + $1.sizeGB }
    }

    // MARK: - Actions

    func download(_ model: AIModel) {
        guard !downloadingIds.contains(model.id) else { return }
        downloadingIds.insert(model.id)
        connectingIds.insert(model.id)
        downloadProgress[model.id] = 0

        Task {
            do {
                try await InferenceService.shared.preloadModel(model) { [weak self] completed, total, fileFraction in
                    Task { @MainActor [weak self] in
                        guard let self else { return }

                        // First callback — leave connecting state
                        if self.connectingIds.contains(model.id) {
                            self.connectingIds.remove(model.id)
                        }

                        // Smooth progress: completed files + byte-fraction of current file
                        // Prevents "frozen" bar while a large shard is mid-download
                        let fraction: Double
                        if total > 0 {
                            fraction = min((Double(completed) + fileFraction) / Double(total), 1.0)
                        } else {
                            fraction = 0
                        }
                        self.downloadProgress[model.id] = fraction
                    }
                }
                await markDownloaded(model.id)
            } catch {
                await fail(model.id, message: error.localizedDescription)
            }
            await endDownload(model.id)
        }
    }

    func retry(_ model: AIModel) {
        failedIds.remove(model.id)
        download(model)
    }

    func delete(_ model: AIModel) {
        InferenceService.shared.evictModel(model)
        setDownloaded(model.id, value: false)
    }

    // MARK: - Private

    @MainActor private func markDownloaded(_ id: String) { setDownloaded(id, value: true) }

    @MainActor private func endDownload(_ id: String) {
        downloadingIds.remove(id)
        connectingIds.remove(id)
        downloadProgress.removeValue(forKey: id)
        // keep failedIds as-is so UI can show retry
    }

    @MainActor private func fail(_ id: String, message: String) {
        failedIds.insert(id)
        errorMessage = "Ошибка загрузки: \(message)"
    }

    private func setDownloaded(_ id: String, value: Bool) {
        if let i = models.firstIndex(where: { $0.id == id }) { models[i].isDownloaded = value }
        var saved = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        if value { saved.insert(id) } else { saved.remove(id) }
        UserDefaults.standard.set(Array(saved), forKey: key)
    }

    private func reload() {
        let downloaded = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        models = AIModel.catalog.map { var m = $0; m.isDownloaded = downloaded.contains(m.id); return m }
    }
}
