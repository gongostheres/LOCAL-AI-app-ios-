import Foundation
import SwiftUI

enum ModelCategory: String, Codable, CaseIterable {
    case medium = "3–4 ГБ"
    case large  = "4+ ГБ"
}

struct AIModel: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let sizeGB: Double
    let minRAMGB: Int
    let category: ModelCategory
    let contextLength: Int
    let iconName: String
    let accentHex: String
    let badge: String?
    var isDownloaded: Bool = false

    var accentColor: Color { Color(hex: accentHex) }

    static let catalog: [AIModel] = [
        AIModel(
            id: "mlx-community/Phi-3.5-mini-instruct-4bit",
            name: "Phi-3.5 Mini",
            subtitle: "Microsoft · 3.8B · быстрый, умный reasoning",
            sizeGB: 2.2, minRAMGB: 4, category: .medium,
            contextLength: 128000,
            iconName: "bolt.fill", accentHex: "5E5CE6", badge: nil
        ),
        AIModel(
            id: "mlx-community/gemma-3-4b-it-4bit",
            name: "Gemma 3",
            subtitle: "Google DeepMind · 4B · отличные диалоги",
            sizeGB: 2.5, minRAMGB: 6, category: .medium,
            contextLength: 8192,
            iconName: "atom", accentHex: "34C759", badge: nil
        ),
        AIModel(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            name: "Mistral 7B",
            subtitle: "Mistral AI · 7B · уровень GPT-3.5",
            sizeGB: 4.1, minRAMGB: 8, category: .large,
            contextLength: 32768,
            iconName: "wind", accentHex: "FF9F0A", badge: nil
        ),
        AIModel(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            name: "Qwen 2.5",
            subtitle: "Alibaba · 7B · лучший выбор для iPhone 15 Pro",
            sizeGB: 4.5, minRAMGB: 8, category: .large,
            contextLength: 32768,
            iconName: "crown.fill", accentHex: "FF375F", badge: "Лучший"
        ),
    ]
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
