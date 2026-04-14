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
    private let lock = NSLock()

    private init() {}

    // MARK: - Session Management

    func prepareSession(
        for model: AIModel,
        conversationId: UUID,
        systemPrompt: String
    ) async throws {
        let container = try await loadContainer(for: model)
        lock.lock()
        if activeConversationId != conversationId || activeSession == nil {
            activeSession = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: GenerateParameters(temperature: 0.7, topP: 0.9)
            )
            activeConversationId = conversationId
        }
        lock.unlock()
    }

    func invalidateSession() {
        lock.lock()
        activeSession = nil
        activeConversationId = nil
        lock.unlock()
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

        lock.lock()
        guard let session = activeSession else {
            lock.unlock()
            throw InferenceError.noSession
        }
        lock.unlock()

        let start = Date()
        var charCount = 0

        for try await chunk in session.streamResponse(to: userMessage) {
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

    func preloadModel(_ model: AIModel, onProgress: @escaping (Double) -> Void) async throws {
        _ = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(id: model.id),
            progressHandler: { onProgress($0.fractionCompleted) }
        )
    }

    // MARK: - Evict

    func evictModel(_ model: AIModel) {
        lock.lock()
        if loadedModelId == model.id {
            loadedContainer = nil
            loadedModelId = nil
            activeSession = nil
            activeConversationId = nil
        }
        lock.unlock()
        let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface/models/\(model.id.replacingOccurrences(of: "/", with: "--"))")
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func loadContainer(for model: AIModel) async throws -> ModelContainer {
        lock.lock()
        if loadedModelId == model.id, let c = loadedContainer {
            lock.unlock()
            return c
        }
        lock.unlock()
        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: ModelConfiguration(id: model.id),
            progressHandler: { _ in }
        )
        lock.lock()
        loadedContainer = container
        loadedModelId = model.id
        lock.unlock()
        return container
    }
}

enum InferenceError: Error {
    case noSession
}
