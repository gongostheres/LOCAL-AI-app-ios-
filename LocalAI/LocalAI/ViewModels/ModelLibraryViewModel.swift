import Foundation
import Observation

@Observable
final class ModelLibraryViewModel {

    var models: [AIModel] = []
    var downloadProgress: [String: Double] = [:]
    var downloadingIds: Set<String> = []
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
        downloadProgress[model.id] = 0
        Task {
            do {
                try await InferenceService.shared.preloadModel(model) { [weak self] p in
                    Task { @MainActor [weak self] in self?.downloadProgress[model.id] = p }
                }
                await markDownloaded(model.id)
            } catch {
                await fail(model.id, message: error.localizedDescription)
            }
            await endDownload(model.id)
        }
    }

    func delete(_ model: AIModel) {
        InferenceService.shared.evictModel(model)
        setDownloaded(model.id, value: false)
    }

    // MARK: - Private

    @MainActor private func markDownloaded(_ id: String) { setDownloaded(id, value: true) }
    @MainActor private func endDownload(_ id: String) {
        downloadingIds.remove(id)
        downloadProgress.removeValue(forKey: id)
    }
    @MainActor private func fail(_ id: String, message: String) {
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
