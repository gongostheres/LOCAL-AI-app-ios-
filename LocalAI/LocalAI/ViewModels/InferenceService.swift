import Foundation
import MLX
import MLXLLM
import MLXLMCommon

final class InferenceService: @unchecked Sendable {
    static let shared = InferenceService()

    private var loadedContainer: ModelContainer?
    private var loadedModelId: String?
    private var activeSession: ChatSession?
    private var activeConversationId: UUID?
    // os_unfair_lock is safe across async/await (no thread pinning, non-blocking)
    private var _lock = os_unfair_lock()

    private init() {}

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(&_lock)
        defer { os_unfair_lock_unlock(&_lock) }
        return try body()
    }

    // MARK: - Session Management

    func prepareSession(
        for model: AIModel,
        conversationId: UUID,
        systemPrompt: String
    ) async throws {
        let container = try await loadContainer(for: model)
        withLock {
            if activeConversationId != conversationId || activeSession == nil {
                activeSession = ChatSession(
                    container,
                    instructions: systemPrompt,
                    generateParameters: GenerateParameters(temperature: 0.6, topP: 0.9)
                )
                activeConversationId = conversationId
            }
        }
    }

    func invalidateSession() {
        withLock {
            activeSession = nil
            activeConversationId = nil
        }
    }

    // MARK: - Streaming generation

    func generate(
        userMessage: String,
        model: AIModel,
        conversationId: UUID,
        systemPrompt: String,
        onToken: @escaping (String) -> Void,
        onSpeed: @escaping (Double) -> Void
    ) async throws {
        try await prepareSession(for: model, conversationId: conversationId, systemPrompt: systemPrompt)

        let session = try withLock {
            guard let s = activeSession else { throw InferenceError.noSession }
            return s
        }

        let start = Date()
        var charCount = 0

        for try await chunk in session.streamResponse(to: userMessage) {
            try Task.checkCancellation()
            onToken(chunk)
            charCount += chunk.count
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0.5 && charCount > 10 {
                let approxTokens = Double(charCount) / 3.5
                onSpeed(approxTokens / elapsed)
            }
        }
    }

    // MARK: - Preload

    func preloadModel(
        _ model: AIModel,
        onProgress: @escaping (_ completed: Int64, _ total: Int64, _ fileFraction: Double) -> Void
    ) async throws {
        do {
            _ = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: model.id),
                progressHandler: { progress in
                    // fileFraction = byte-level progress within the current file (0→1)
                    onProgress(progress.completedUnitCount, progress.totalUnitCount, progress.fractionCompleted)
                }
            )
        } catch {
            throw InferenceService.classifyError(error)
        }
    }

    // MARK: - Evict

    func evictModel(_ model: AIModel) {
        withLock {
            if loadedModelId == model.id {
                loadedContainer = nil
                loadedModelId = nil
                activeSession = nil
                activeConversationId = nil
            }
        }
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/\(model.id.replacingOccurrences(of: "/", with: "--"))")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func loadContainer(for model: AIModel) async throws -> ModelContainer {
        if let cached = withLock({ loadedModelId == model.id ? loadedContainer : nil }) {
            return cached
        }
        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: ModelConfiguration(id: model.id),
                progressHandler: { _ in }
            )
            withLock {
                loadedContainer = container
                loadedModelId = model.id
            }
            return container
        } catch {
            throw InferenceService.classifyError(error)
        }
    }

    /// Converts low-level errors to InferenceError.outOfMemory when appropriate.
    /// Checks POSIX error codes first (locale-independent), then falls back to
    /// English + Russian keyword matching in the localised description.
    private static func classifyError(_ error: Error) -> Error {
        let ns = error as NSError
        let isMemoryPressure =
            ns.domain == NSPOSIXErrorDomain && (ns.code == Int(ENOMEM) || ns.code == Int(EINVAL))
            || ns.code == Int(ENOMEM)
        if isMemoryPressure { return InferenceError.outOfMemory }

        let msg = ns.localizedDescription.lowercased()
        let keywords = ["memory", "allocation", "killed", "out of memory",
                        "память", "выделение", "нехватка"]
        if keywords.contains(where: msg.contains) { return InferenceError.outOfMemory }

        return error
    }
}

enum InferenceError: LocalizedError {
    case noSession
    case outOfMemory

    var errorDescription: String? {
        switch self {
        case .noSession: return "Сессия не инициализирована"
        case .outOfMemory: return "Недостаточно памяти. Попробуйте Llama 3.2 или Phi-3.5 Mini"
        }
    }
}
