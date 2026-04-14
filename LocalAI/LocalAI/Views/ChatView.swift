import SwiftUI

struct ChatView: View {
    @Environment(ChatViewModel.self) private var vm
    @Environment(ModelLibraryViewModel.self) private var libraryVM
    @Binding var selectedTab: Int
    @State private var showHistory = false
    @State private var showModelPicker = false
    @State private var floatingIcon = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AmbientBackground()

            VStack(spacing: 0) {
                chatHeader
                messagesList
            }

            inputBar
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showHistory) {
            ConversationListView(isPresented: $showHistory)
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(isPresented: $showModelPicker, selectedTab: $selectedTab)
        }
        .alert("Ошибка", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
    }

    // MARK: - Header

    private var chatHeader: some View {
        ZStack {
            // Blur background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
                .frame(height: 54)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                }

            HStack(spacing: 0) {
                // History button
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.txt2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressButtonStyle())

                Spacer()

                // Model selector
                Button { showModelPicker = true } label: {
                    HStack(spacing: 8) {
                        if let model = vm.selectedModel {
                            Image(systemName: model.iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(model.color1)
                            Text(model.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.txt1)
                            if vm.currentSpeed > 0 && vm.isGenerating {
                                Text(String(format: "%.0f t/s", vm.currentSpeed))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(model.color1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(model.color1.opacity(0.15), in: Capsule())
                                    .transition(.scale.combined(with: .opacity))
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.txt3)
                        } else {
                            Text("Выбрать модель")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.violet)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.violet)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background {
                        Capsule()
                            .fill(Color.white.opacity(0.07))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
                    }
                }
                .buttonStyle(PressButtonStyle())
                .animation(.spring(response: 0.3), value: vm.isGenerating)

                Spacer()

                // New chat
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let model = vm.selectedModel { vm.newConversation(model: model) }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 18))
                        .foregroundStyle(vm.selectedModel == nil ? Color.txt3 : Color.txt2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressButtonStyle())
                .disabled(vm.selectedModel == nil)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 54)
    }

    // MARK: - Messages list

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(vm.displayMessages) { msg in
                        ChatBubble(message: msg)
                            .id(msg.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: msg.role == .user ? .trailing : .leading).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                    if vm.isGenerating {
                        StreamingChatBubble(text: vm.streamingContent, isModelLoading: vm.isModelLoading)
                            .id("stream")
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Color.clear.frame(height: 86).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .animation(.spring(response: 0.35), value: vm.displayMessages.count)
            }
            .onChange(of: vm.displayMessages.count) {
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom") }
            }
            .onChange(of: vm.streamingContent) {
                proxy.scrollTo("stream", anchor: .bottom)
            }
            .overlay {
                if vm.displayMessages.isEmpty && !vm.isGenerating {
                    emptyState
                }
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 32) {
            if let model = vm.selectedModel {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [model.color1.opacity(0.25), .clear],
                                    center: .center, startRadius: 0, endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                        Image(systemName: model.iconName)
                            .font(.system(size: 44, weight: .thin))
                            .foregroundStyle(model.color1)
                            .glow(model.color1, radius: 12)
                            .offset(y: floatingIcon ? -8 : 0)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                                    floatingIcon = true
                                }
                            }
                    }
                    Text(model.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.txt1)
                    Text("Начните разговор")
                        .font(.subheadline)
                        .foregroundStyle(Color.txt2)
                }

                suggestedPrompts
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 52, weight: .thin))
                        .foregroundStyle(Color.txt3)
                    Text("Выберите модель")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.txt2)
                    Button { showModelPicker = true } label: {
                        Text("Открыть каталог")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                Color.violet,
                                in: Capsule()
                            )
                            .glow(Color.violet, radius: 12)
                    }
                    .buttonStyle(PressButtonStyle())
                }
            }
        }
    }

    private var suggestedPrompts: some View {
        VStack(spacing: 8) {
            ForEach(["Объясни квантовые вычисления просто", "Напиши функцию на Swift для сортировки", "Придумай идею для стартапа"], id: \.self) { prompt in
                Button {
                    vm.inputText = prompt
                    vm.send()
                } label: {
                    HStack {
                        Text(prompt)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.txt2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.txt3)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassCard(radius: 14)
                }
                .buttonStyle(PressButtonStyle())
            }
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        @Bindable var bvm = vm
        return HStack(alignment: .bottom, spacing: 10) {
            TextField("Сообщение...", text: $bvm.inputText, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(Color.txt1)
                .tint(Color.violet)
                .lineLimit(1...6)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .disabled(vm.isGenerating)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                vm.send()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(canSend
                                ? AnyShapeStyle(Color.violet)
                                : AnyShapeStyle(Color.white.opacity(0.08))
                            )
                    }
                    .glow(canSend ? Color.violet : .clear, radius: 10)
            }
            .buttonStyle(PressButtonStyle())
            .disabled(!canSend)
            .padding(.trailing, 6)
            .padding(.bottom, 6)
            .animation(.spring(response: 0.3), value: canSend)
        }
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            vm.isGenerating
                                ? AnyShapeStyle(Color.violet.opacity(0.4))
                                : AnyShapeStyle(Color.borderHi),
                            lineWidth: 1
                        )
                }
                .shadow(color: vm.isGenerating ? Color.violet.opacity(0.25) : .clear, radius: 20)
        }
        .animation(.easeInOut(duration: 0.4), value: vm.isGenerating)
    }

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty && vm.selectedModel != nil && !vm.isGenerating
    }
}

// MARK: - Model picker sheet

private struct ModelPickerSheet: View {
    @Environment(ChatViewModel.self) private var chatVM
    @Environment(ModelLibraryViewModel.self) private var libraryVM
    @Binding var isPresented: Bool
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(libraryVM.downloadedModels) { model in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                chatVM.selectedModel = model
                                isPresented = false
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(model.color1.opacity(0.15))
                                            .frame(width: 52, height: 52)
                                        Image(systemName: model.iconName)
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(model.color1)
                                    }
                                    .glow(model.color1, radius: 8)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(model.name).font(.headline).foregroundStyle(Color.txt1)
                                        Text(model.subtitle).font(.caption).foregroundStyle(Color.txt2).lineLimit(1)
                                    }
                                    Spacer()
                                    if chatVM.selectedModel?.id == model.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(model.color1)
                                            .glow(model.color1, radius: 6)
                                    }
                                }
                                .padding(16)
                                .glassCard(radius: 18, glow: chatVM.selectedModel?.id == model.id ? model.glowColor : .clear)
                            }
                            .buttonStyle(PressButtonStyle())
                        }

                        if libraryVM.downloadedModels.isEmpty {
                            VStack(spacing: 20) {
                                ZStack {
                                    Circle()
                                        .fill(Color.violet.opacity(0.12))
                                        .frame(width: 88, height: 88)
                                    Image(systemName: "arrow.down.to.line")
                                        .font(.system(size: 36, weight: .thin))
                                        .foregroundStyle(Color.violet)
                                        .glow(Color.violet, radius: 8)
                                }
                                VStack(spacing: 6) {
                                    Text("Нет загруженных моделей")
                                        .font(.headline)
                                        .foregroundStyle(Color.txt1)
                                    Text("Скачайте модель — это займёт пару минут")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.txt3)
                                        .multilineTextAlignment(.center)
                                }
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    isPresented = false
                                    withAnimation { selectedTab = 1 }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "cpu")
                                            .font(.system(size: 15, weight: .semibold))
                                        Text("Открыть библиотеку")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 28)
                                    .padding(.vertical, 14)
                                    .background(
                                        Color.violet,
                                        in: Capsule()
                                    )
                                    .glow(Color.violet, radius: 12)
                                }
                                .buttonStyle(PressButtonStyle())
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 48)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Выбор модели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { isPresented = false }
                        .foregroundStyle(Color.violet)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    private var isUser: Bool { message.role == .user }
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if isUser { Spacer(minLength: 52) }

            if !isUser {
                ZStack {
                    Circle().fill(Color.surfaceHi).frame(width: 28, height: 28)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.violet)
                }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 5) {
                Text(message.content)
                    .font(.system(size: 16))
                    .foregroundStyle(isUser ? .white : Color.txt1)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        if isUser {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.violet)
                        } else {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.surfaceHi)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .strokeBorder(Color.borderHi, lineWidth: 0.5)
                                }
                        }
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } label: { Label("Копировать", systemImage: "doc.on.doc") }
                    }

                if let tps = message.tokensPerSecond, tps > 0 {
                    Text(String(format: "%.0f tok/s", tps))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.violet.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.violet.opacity(0.08), in: Capsule())
                }
            }

            if !isUser { Spacer(minLength: 52) }
        }
        .padding(.vertical, 2)
        .scaleEffect(appeared ? 1 : 0.72, anchor: isUser ? .bottomTrailing : .bottomLeading)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.60)) {
                appeared = true
            }
        }
    }
}

// MARK: - Streaming bubble

struct StreamingChatBubble: View {
    let text: String
    let isModelLoading: Bool
    @State private var dotPhase = 0
    @State private var brainScale: CGFloat = 1.0
    private let timer = Timer.publish(every: 0.38, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack {
                Circle().fill(Color.surfaceHi).frame(width: 28, height: 28)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.violet)
                    .scaleEffect(brainScale)
            }
            .glow(Color.violet.opacity(0.4), radius: 6)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    brainScale = 1.18
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if isModelLoading {
                    loadingLabel
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                } else if text.isEmpty {
                    thinkingDots
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                } else {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.txt1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.surfaceHi)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.violet.opacity(0.35), lineWidth: 1)
                    }
            }

            Spacer(minLength: 52)
        }
        .padding(.vertical, 2)
    }

    private var loadingLabel: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Color.violet)
                .scaleEffect(0.75)
            Text("Загружаю модель...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.txt2)
        }
    }

    private var thinkingDots: some View {
        HStack(spacing: 7) {
            ForEach(0..<3) { i in
                Circle()
                    .frame(width: 7, height: 7)
                    .foregroundStyle(
                        dotPhase == i ? Color.violet : Color.white.opacity(0.18)
                    )
                    .scaleEffect(dotPhase == i ? 1.3 : 0.8)
                    .offset(y: dotPhase == i ? -5 : 0)
                    .shadow(color: dotPhase == i ? Color.violet.opacity(0.7) : .clear, radius: 5)
                    .animation(.spring(response: 0.28, dampingFraction: 0.55), value: dotPhase)
            }
        }
        .onReceive(timer) { _ in dotPhase = (dotPhase + 1) % 3 }
    }
}
