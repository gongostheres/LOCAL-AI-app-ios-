import Foundation

struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let modelId: String
    let modelName: String
    let createdAt: Date
    var updatedAt: Date

    var preview: String {
        messages.last(where: { $0.role == .assistant })?.content.prefix(80).description
            ?? messages.last?.content.prefix(80).description
            ?? "Новый чат"
    }

    static func new(model: AIModel) -> Conversation {
        let now = Date()
        return Conversation(
            id: UUID(),
            title: "Чат с \(model.name)",
            messages: [],
            modelId: model.id,
            modelName: model.name,
            createdAt: now,
            updatedAt: now
        )
    }
}
