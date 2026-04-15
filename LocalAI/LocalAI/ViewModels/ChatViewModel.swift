import Foundation
import Observation
import UIKit

// MARK: - System Prompt Presets

enum SystemPromptPreset: String, CaseIterable, Codable {
    case assistant  = "assistant"
    case translator = "translator"
    case coder      = "coder"
    case summarizer = "summarizer"

    var displayName: String {
        switch self {
        case .assistant:  "Помощник"
        case .translator: "Переводчик"
        case .coder:      "Кодер"
        case .summarizer: "Суммаризатор"
        }
    }

    var icon: String {
        switch self {
        case .assistant:  "person.fill"
        case .translator: "globe"
        case .coder:      "chevron.left.forwardslash.chevron.right"
        case .summarizer: "text.quote"
        }
    }

    var prompt: String {
        switch self {
        case .assistant:
            return """
            Ты — умный и полезный AI-ассистент. Отвечай чётко и по делу, без лишних предисловий.
            Используй markdown: **жирный** для ключевых слов, ```lang``` для кода, - для списков.
            Отвечай на том языке, на котором задан вопрос. Если на русском — на русском.
            Будь точным и конкретным. Не повторяй вопрос. Не добавляй пустых фраз вроде "Конечно!" или "Отличный вопрос!".
            """
        case .translator:
            return """
            Ты — профессиональный переводчик.
            Правило: если текст на русском — переводи на английский; если на любом другом языке — переводи на русский.
            Сохраняй стиль, тон и структуру оригинала. Если есть идиомы — подбирай эквиваленты, не дословный перевод.
            Выдавай только перевод, без комментариев и объяснений. Если нужны варианты — укажи их в скобках.
            """
        case .coder:
            return """
            Ты — старший разработчик с 10+ годами опыта. Пишешь чистый, идиоматичный код.
            Используй ```lang блоки для всего кода. Объяснения — краткие, только по делу.
            Указывай на потенциальные баги и edge cases. Предпочитай проверенные паттерны экзотическим решениям.
            Если вопрос на русском — объяснения на русском, имена переменных — на английском.
            Не пиши код, который ты бы не поставил в production.
            """
        case .summarizer:
            return """
            Ты — эксперт по анализу и суммаризации текстов.
            Структура ответа: 1-2 предложения сути, затем ключевые тезисы списком (5-7 пунктов).
            Убирай воду, оставляй факты и выводы. Объём резюме — не более 20% от оригинала.
            Отвечай на том же языке, что и входной текст. Используй markdown для структуры.
            """
        }
    }
}

// MARK: - ChatViewModel

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

    var promptPreset: SystemPromptPreset = .assistant {
        didSet {
            UserDefaults.standard.set(promptPreset.rawValue, forKey: "prompt_preset")
            InferenceService.shared.invalidateSession()
        }
    }

    private let saveKey = "conversations_v1"
    private var generationTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        if let raw = UserDefaults.standard.string(forKey: "prompt_preset"),
           let preset = SystemPromptPreset(rawValue: raw) {
            promptPreset = preset
        }
        loadConversations()
    }

    // MARK: - Computed

    var displayMessages: [ChatMessage] {
        currentConversation?.messages ?? []
    }

    var tokenEstimate: Int {
        let ctx = displayMessages.map(\.content).joined(separator: " ")
        return (ctx.count + streamingContent.count) / 4
    }

    var exportText: String {
        guard let conv = currentConversation else { return "" }
        var lines = ["# \(conv.title)", "Модель: \(conv.modelName)", "Дата: \(conv.updatedAt.formatted())", ""]
        for msg in conv.messages {
            let role = msg.role == .user ? "**Вы**" : "**Ассистент**"
            lines.append("\(role): \(msg.content)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
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

    // MARK: - Regenerate

    func regenerate() {
        guard let convId = currentConversation?.id,
              let idx = conversations.firstIndex(where: { $0.id == convId }),
              !isGenerating else { return }

        // Remove trailing assistant messages
        while let last = conversations[idx].messages.last, last.role == .assistant {
            conversations[idx].messages.removeLast()
        }
        currentConversation = conversations[idx]

        guard let lastUser = conversations[idx].messages.last(where: { $0.role == .user }) else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        InferenceService.shared.invalidateSession()
        startGenerating(text: lastUser.content, convId: convId)
    }

    // MARK: - Edit message

    func editMessage(_ msg: ChatMessage, newText: String) {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let convId = currentConversation?.id,
              let convIdx = conversations.firstIndex(where: { $0.id == convId }),
              let msgIdx = conversations[convIdx].messages.firstIndex(where: { $0.id == msg.id }),
              !isGenerating else { return }

        conversations[convIdx].messages[msgIdx].content = trimmed
        conversations[convIdx].messages.removeSubrange((msgIdx + 1)...)
        currentConversation = conversations[convIdx]
        saveConversations()

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        InferenceService.shared.invalidateSession()
        startGenerating(text: trimmed, convId: convId)
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

        startGenerating(text: text, convId: convId)
    }

    // MARK: - Private: Generation

    private func startGenerating(text: String, convId: UUID) {
        guard let model = selectedModel else { return }

        isGenerating = true
        isModelLoading = true
        streamingContent = ""
        currentSpeed = 0

        let systemPrompt = promptPreset.prompt

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
                return
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
