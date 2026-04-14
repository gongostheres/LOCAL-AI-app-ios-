import Foundation

enum MessageRole: String, Codable {
    case user, assistant, system
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    var content: String
    let createdAt: Date
    var tokensPerSecond: Double?

    init(role: MessageRole, content: String, tokensPerSecond: Double? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.createdAt = Date()
        self.tokensPerSecond = tokensPerSecond
    }
}
