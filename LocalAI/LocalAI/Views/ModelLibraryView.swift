import SwiftUI
import Darwin

struct ModelLibraryView: View {
    @Environment(ModelLibraryViewModel.self) private var vm
    @Environment(ChatViewModel.self) private var chatVM
    @Binding var selectedTab: Int

    @State private var freeRAMGB: Double = 0
    private let totalRAMGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824

    var body: some View {
        ZStack {
            AmbientBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    ForEach(Array(vm.models.enumerated()), id: \.element.id) { index, model in
                        ModelCard(
                            model: model,
                            index: index,
                            progress: vm.downloadProgress[model.id],
                            isDownloading: vm.downloadingIds.contains(model.id),
                            isConnecting: vm.connectingIds.contains(model.id),
                            isFailed: vm.failedIds.contains(model.id),
                            onAction: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                if model.isDownloaded {
                                    chatVM.selectedModel = model
                                    withAnimation { selectedTab = 0 }
                                } else {
                                    vm.download(model)
                                }
                            },
                            onRetry: { vm.retry(model) },
                            onDelete: { vm.delete(model) }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
        }
        .preferredColorScheme(.dark)
        .alert("Ошибка", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Модели")
                    .font(.system(size: 32, weight: .black))
                    .gradientForeground([.white, Color.violet.opacity(0.7)])
                Text("\(vm.downloadedModels.count) загружено · \(String(format: "%.1f", vm.totalDownloadedGB)) ГБ")
                    .font(.subheadline)
                    .foregroundStyle(Color.txt2)
            }
            Spacer()
            ramIndicator
        }
        .padding(.top, 8)
        .task {
            while !Task.isCancelled {
                freeRAMGB = Double(os_proc_available_memory()) / 1_073_741_824
                do {
                    try await Task.sleep(nanoseconds: 3_000_000_000)
                } catch {
                    break // cancelled — exit cleanly
                }
            }
        }
    }

    private var ramIndicator: some View {
        let ramColor: Color = freeRAMGB > 3 ? Color(hex: "34C759")
                            : freeRAMGB > 1.5 ? Color(hex: "FF9F0A")
                            : Color(hex: "FF453A")
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "memorychip")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.txt3)
                Text("ОЗУ")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.txt3)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", freeRAMGB))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(ramColor)
                Text("/ \(Int(totalRAMGB.rounded())) ГБ")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.txt3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.borderHi, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Model Card

struct ModelCard: View {
    let model: AIModel
    let index: Int
    let progress: Double?
    let isDownloading: Bool
    let isConnecting: Bool
    let isFailed: Bool
    let onAction: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void

    @State private var expanded = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            mainRow
                .padding(20)

            if isFailed {
                failedRow
            } else if isDownloading {
                if isConnecting {
                    connectingRow
                } else if let p = progress {
                    downloadProgressRow(p)
                }
            }

            if model.isDownloaded && expanded {
                specsRow
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.borderHi, lineWidth: 0.5)
                }
        }
        .shadow(color: model.glowColor, radius: expanded ? 10 : 6)
        .scaleEffect(appeared ? 1 : 0.84)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 22)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.62).delay(Double(index) * 0.07)) {
                appeared = true
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                expanded.toggle()
            }
        }
        .contextMenu {
            if model.isDownloaded {
                Button(role: .destructive, action: onDelete) {
                    Label("Удалить модель", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [model.color1.opacity(0.15), model.color2.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(model.color1.opacity(0.15), lineWidth: 0.5)
                    }
                Image(systemName: model.iconName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(model.color1)
            }
            .glow(model.color1, radius: 6)

            // Text
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.txt1)
                    if let badge = model.badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .black))
                            .tracking(0.3)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(model.color1.opacity(0.2))
                                    .overlay(Capsule().strokeBorder(model.color1.opacity(0.4), lineWidth: 0.5))
                            )
                            .foregroundStyle(model.color1)
                    }
                    if model.isDownloaded {
                        Circle()
                            .fill(Color(hex: "34C759"))
                            .frame(width: 7, height: 7)
                            .glow(Color(hex: "34C759"), radius: 4)
                    }
                }
                Text(model.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.txt2)
                    .lineLimit(1)

                // Size tag
                HStack(spacing: 6) {
                    sizeTag("\(String(format: "%.1f", model.sizeGB)) ГБ", icon: "arrow.down.circle")
                    sizeTag("\(model.contextLength / 1024)k ctx", icon: "text.alignleft")
                }
            }

            Spacer()

            actionButton
        }
    }

    private func sizeTag(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(Color.txt3)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.white.opacity(0.05), in: Capsule())
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if isDownloading {
            ProgressView()
                .tint(model.color1)
                .frame(width: 44, height: 44)
        } else if isFailed {
            Button(action: onRetry) {
                ZStack {
                    Circle()
                        .fill(Color(hex: "FF453A").opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(hex: "FF453A"))
                }
            }
            .buttonStyle(PressButtonStyle())
        } else if model.isDownloaded {
            Button(action: onAction) {
                Image(systemName: "message.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(
                            LinearGradient(colors: [model.color1, model.color2], startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .glow(model.color1, radius: 10)
            }
            .buttonStyle(PressButtonStyle())
        } else {
            Button(action: onAction) {
                ZStack {
                    Circle()
                        .strokeBorder(model.color1.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(model.color1)
                }
            }
            .buttonStyle(PressButtonStyle())
        }
    }

    // MARK: - Failed row

    private var failedRow: some View {
        VStack(spacing: 0) {
            Divider().background(Color.borderHi)
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: "FF453A"))
                Text("Ошибка загрузки")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "FF453A").opacity(0.8))
                Spacer()
                Button(action: onRetry) {
                    Text("Повторить")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: "FF453A"))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Connecting row

    private var connectingRow: some View {
        VStack(spacing: 0) {
            Divider().background(Color.borderHi)
            HStack(spacing: 10) {
                ProgressView()
                    .tint(model.color1)
                    .scaleEffect(0.75)
                Text("Подключение к серверу...")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.txt3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Download progress

    private func downloadProgressRow(_ p: Double) -> some View {
        VStack(spacing: 10) {
            Divider().background(Color.borderHi)
            HStack(spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.06)).frame(height: 4)
                        Capsule()
                            .fill(model.color1)
                            .frame(width: geo.size.width * p, height: 4)
                            .animation(.easeOut(duration: 0.4), value: p)
                    }
                }
                .frame(height: 4)
                Text(String(format: "%.0f%%", p * 100))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(model.color1)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    // MARK: - Specs

    private var specsRow: some View {
        VStack(spacing: 0) {
            Divider().background(Color.borderHi)
            HStack(spacing: 0) {
                specCell(value: "\(String(format: "%.1f", model.sizeGB)) ГБ", label: "Размер")
                Divider().frame(height: 32).background(Color.borderHi)
                specCell(value: "\(model.minRAMGB)+ ГБ", label: "RAM")
                Divider().frame(height: 32).background(Color.borderHi)
                specCell(value: "\(model.contextLength / 1024)k", label: "Контекст")
            }
            .padding(.vertical, 14)
        }
    }

    private func specCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.txt1)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.txt3)
        }
        .frame(maxWidth: .infinity)
    }
}
