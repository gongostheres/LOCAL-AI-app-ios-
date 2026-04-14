import Foundation
import Observation
import UIKit

@Observable
final class ChatViewModel {

    // MARK: - State
    var conversations: [Conversation] = []
    var currentConversation: Conversation?
    var selectedModel: AIModel?

    var inputText: String = ""
    var isGenerating: Bool = false
    var isModelLoading: Bool = false
    var streamingContent: String = ""
    var currentSpeed: Double = 0
    var errorMessage: String?

    private let systemPrompt = "Ты — умный и полезный AI-ассистент. Отвечай на русском, если вопрос задан на русском."
    private let saveKey = "conversations_v1"
    private var generationTask: Task<Void, Never>?

    // MARK: - Init

    init() { loadConversations() }

    // MARK: - Computed

    var displayMessages: [ChatMessage] {
        currentConversation?.messages ?? []
    }

    // MARK: - Conversations

    func newConversation(model: AIModel? = nil) {
        let mdl = model ?? selectedModel
        guard let mdl else { return }
        let conv = Conversation.new(model: mdl)
        conversations.insert(conv, at: 0)
        currentConversation = conv
        selectedModel = mdl
        InferenceService.shared.invalidateSession()
        saveConversations()
    }

    func selectConversation(_ conv: Conversation) {
        currentConversation = conv
        InferenceService.shared.invalidateSession()
        if let mdl = AIModel.catalog.first(where: { $0.id == conv.modelId }) {
            selectedModel = mdl
        }
    }

    func deleteConversation(_ conv: Conversation) {
        conversations.removeAll { $0.id == conv.id }
        if currentConversation?.id == conv.id {
            currentConversation = conversations.first
        }
        saveConversations()
    }

    func renameConversation(_ conv: Conversation, to title: String) {
        guard let idx = conversations.firstIndex(where: { $0.id == conv.id }) else { return }
        conversations[idx].title = title
        if currentConversation?.id == conv.id {
            currentConversation?.title = title
        }
        saveConversations()
    }

    func deleteMessage(_ msg: ChatMessage) {
        guard let convId = currentConversation?.id,
              let idx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        conversations[idx].messages.removeAll { $0.id == msg.id }
        currentConversation = conversations[idx]
        saveConversations()
    }

    // MARK: - Stop

    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
        let partial = streamingContent
        let convId = currentConversation?.id
        Task { @MainActor in
            if !partial.isEmpty, let id = convId {
                self.commit(partial, speed: self.currentSpeed, to: id)
            }
            self.finishGenerating()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Send

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let model = selectedModel, !isGenerating else { return }

        if currentConversation == nil { newConversation(model: model) }
        guard let convId = currentConversation?.id else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        inputText = ""
        appendMessage(ChatMessage(role: .user, content: text), to: convId)

        // Auto-title from first user message
        if let idx = conversations.firstIndex(where: { $0.id == convId }),
           conversations[idx].messages.filter({ $0.role == .user }).count == 1 {
            let title = String(text.prefix(50))
            conversations[idx].title = title
            if currentConversation?.id == convId { currentConversation?.title = title }
            saveConversations()
        }

        isGenerating = true
        isModelLoading = true
        streamingContent = ""
        currentSpeed = 0

        generationTask = Task {
            do {
                var full = ""
                var lastSpeed = 0.0
                var firstToken = true
                try await InferenceService.shared.generate(
                    userMessage: text,
                    model: model,
                    conversationId: convId,
                    systemPrompt: systemPrompt,
                    onToken: { [weak self] chunk in
                        full += chunk
                        // Fix: check/set firstToken here (background side) before dispatching
                        // to MainActor, avoiding a data race between concurrent inner Tasks
                        let isFirst = firstToken
                        if firstToken { firstToken = false }
                        Task { @MainActor [weak self] in
                            if isFirst {
                                self?.isModelLoading = false
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                            self?.streamingContent = full
                        }
                    },
                    onSpeed: { speed in
                        lastSpeed = speed
                        Task { @MainActor [weak self] in self?.currentSpeed = speed }
                    }
                )
                await commit(full, speed: lastSpeed, to: convId)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch is CancellationError {
                return // stopGeneration() already committed partial + called finishGenerating()
            } catch {
                await setError(error.localizedDescription)
            }
            await finishGenerating()
        }
    }

    // MARK: - Private helpers

    private func appendMessage(_ msg: ChatMessage, to convId: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == convId }) else { return }
        conversations[idx].messages.append(msg)
        conversations[idx].updatedAt = Date()
        if currentConversation?.id == convId { currentConversation = conversations[idx] }
    }

    @MainActor
    private func commit(_ text: String, speed: Double, to convId: UUID) {
        streamingContent = ""
        let msg = ChatMessage(role: .assistant, content: text, tokensPerSecond: speed > 0 ? speed : nil)
        appendMessage(msg, to: convId)
        saveConversations()
    }

    @MainActor
    private func finishGenerating() {
        isGenerating = false
        isModelLoading = false
        currentSpeed = 0
        generationTask = nil
    }

    @MainActor
    private func setError(_ msg: String) {
        errorMessage = msg
        isGenerating = false
        isModelLoading = false
        streamingContent = ""
        generationTask = nil
    }

    // MARK: - Persistence

    private func saveConversations() {
        let toSave = Array(conversations.prefix(50))
        if let data = try? JSONEncoder().encode(toSave) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }

    private func loadConversations() {
        guard let data = UserDefaults.standard.data(forKey: saveKey),
              let loaded = try? JSONDecoder().decode([Conversation].self, from: data)
        else { return }
        conversations = loaded
        currentConversation = loaded.first
        if let first = loaded.first,
           let mdl = AIModel.catalog.first(where: { $0.id == first.modelId }) {
            selectedModel = mdl
        }
    }
}
