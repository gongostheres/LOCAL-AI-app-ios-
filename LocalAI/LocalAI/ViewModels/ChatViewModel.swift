import Foundation
import Observation

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

    // MARK: - Init

    init() {
        loadConversations()
    }

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

    // MARK: - Send

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let model = selectedModel, !isGenerating else { return }

        if currentConversation == nil {
            newConversation(model: model)
        }
        guard let convId = currentConversation?.id else { return }

        inputText = ""
        appendMessage(ChatMessage(role: .user, content: text), to: convId)
        isGenerating = true
        isModelLoading = true
        streamingContent = ""
        currentSpeed = 0

        Task {
            do {
                var full = ""
                var lastSpeed = 0.0
                try await InferenceService.shared.generate(
                    userMessage: text,
                    model: model,
                    conversationId: convId,
                    systemPrompt: systemPrompt,
                    onToken: { [weak self] chunk in
                        full += chunk
                        Task { @MainActor [weak self] in
                            self?.isModelLoading = false
                            self?.streamingContent = full
                        }
                    },
                    onSpeed: { speed in
                        lastSpeed = speed
                        Task { @MainActor [weak self] in
                            self?.currentSpeed = speed
                        }
                    }
                )
                await commit(full, speed: lastSpeed, to: convId)
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
        if currentConversation?.id == convId {
            currentConversation = conversations[idx]
        }
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
    }

    @MainActor
    private func setError(_ msg: String) {
        errorMessage = msg
        isGenerating = false
        isModelLoading = false
        streamingContent = ""
    }

    // MARK: - Persistence

    private func saveConversations() {
        let maxConversations = 50
        let toSave = Array(conversations.prefix(maxConversations))
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
