import SwiftUI
import Speech
import AVFoundation

// MARK: - Voice Input Controller

@Observable
final class VoiceInputController: NSObject {
    var isRecording = false
    var permissionError: String?

    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    func toggle(onPartial: @escaping (String) -> Void) {
        if isRecording { stop() } else { requestAndStart(onPartial: onPartial) }
    }

    func stop() {
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func requestAndStart(onPartial: @escaping (String) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self else { return }
            guard status == .authorized else {
                Task { @MainActor [weak self] in
                    self?.permissionError = "Разрешение на распознавание речи отклонено. Включите в Настройках."
                }
                return
            }
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    Task { @MainActor [weak self] in
                        self?.permissionError = "Разрешение на микрофон отклонено. Включите в Настройках."
                    }
                    return
                }
                self.startRecording(onPartial: onPartial)
            }
        }
    }

    private func startRecording(onPartial: @escaping (String) -> Void) {
        recognitionTask?.cancel()
        recognitionTask = nil

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in onPartial(text) }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor [weak self] in self?.stop() }
            }
        }

        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            Task { @MainActor [weak self] in self?.isRecording = true }
        } catch {
            Task { @MainActor [weak self] in
                self?.permissionError = "Ошибка аудио: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - ChatView

struct ChatView: View {
    @Environment(ChatViewModel.self) private var vm
    @Environment(ModelLibraryViewModel.self) private var libraryVM
    @Binding var selectedTab: Int
    @State private var showHistory = false
    @State private var showModelPicker = false
    @State private var showSettings = false
    @State private var floatingIcon = false
    @State private var editingMessage: ChatMessage?
    @State private var voice = VoiceInputController()

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
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
        }
        .sheet(item: $editingMessage) { msg in
            EditMessageSheet(message: msg) { newText in
                vm.editMessage(msg, newText: newText)
                editingMessage = nil
            }
        }
        .alert("Ошибка", isPresented: .constant(vm.errorMessage != nil)) {
            Button("OK") { vm.errorMessage = nil }
        } message: { Text(vm.errorMessage ?? "") }
        .alert("Микрофон", isPresented: .constant(voice.permissionError != nil)) {
            Button("OK") { voice.permissionError = nil }
        } message: { Text(voice.permissionError ?? "") }
    }

    // MARK: - Header

    private var chatHeader: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
                .frame(height: 54)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)
                }

            HStack(spacing: 0) {
                // History
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.txt2)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressButtonStyle())

                Spacer()

                // Model selector with token count
                Button { showModelPicker = true } label: {
                    HStack(spacing: 8) {
                        if let model = vm.selectedModel {
                            Image(systemName: model.iconName)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(model.color1)
                            Text(model.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.txt1)
                            if vm.isGenerating && vm.currentSpeed > 0 {
                                Text(String(format: "%.0f t/s", vm.currentSpeed))
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(model.color1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(model.color1.opacity(0.15), in: Capsule())
                                    .transition(.scale.combined(with: .opacity))
                            } else if !vm.isGenerating && vm.tokenEstimate > 0 {
                                let tokStr = vm.tokenEstimate > 1000
                                    ? String(format: "~%.1fk", Double(vm.tokenEstimate) / 1000)
                                    : "~\(vm.tokenEstimate)"
                                Text("\(tokStr) tok")
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.txt3)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.05), in: Capsule())
                                    .transition(.opacity)
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
                .animation(.spring(response: 0.3), value: vm.tokenEstimate)

                Spacer()

                // New chat
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if let model = vm.selectedModel { vm.newConversation(model: model) }
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17))
                        .foregroundStyle(vm.selectedModel == nil ? Color.txt3 : Color.txt2)
                        .frame(width: 38, height: 44)
                }
                .buttonStyle(PressButtonStyle())
                .disabled(vm.selectedModel == nil)

                // Settings
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.txt2)
                        .frame(width: 38, height: 44)
                }
                .buttonStyle(PressButtonStyle())
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 54)
    }

    // MARK: - Messages list

    private var messagesList: some View {
        let lastAIId = vm.displayMessages.last(where: { $0.role == .assistant })?.id

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(vm.displayMessages) { msg in
                        ChatBubble(
                            message: msg,
                            isLastAI: msg.id == lastAIId && !vm.isGenerating,
                            onRegenerate: msg.id == lastAIId && !vm.isGenerating ? { vm.regenerate() } : nil,
                            onEdit: msg.role == .user ? { editingMessage = msg } : nil
                        )
                        .id(msg.id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.72, anchor: msg.role == .user ? .bottomTrailing : .bottomLeading).combined(with: .opacity),
                            removal: .opacity
                        ))
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if msg.role == .user {
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    editingMessage = msg
                                } label: {
                                    Label("Изменить", systemImage: "pencil")
                                }
                                .tint(Color.violet)
                            }
                            Button(role: .destructive) {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                vm.deleteMessage(msg)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        }
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
                            .background(Color.violet, in: Capsule())
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
        return HStack(alignment: .bottom, spacing: 8) {
            // Mic button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                voice.toggle { partial in
                    bvm.inputText = partial
                }
            } label: {
                Image(systemName: voice.isRecording ? "waveform" : "mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(voice.isRecording ? Color.violet : Color.txt3)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle()
                            .fill(voice.isRecording
                                  ? Color.violet.opacity(0.15)
                                  : Color.white.opacity(0.05))
                            .overlay {
                                if voice.isRecording {
                                    Circle().strokeBorder(Color.violet.opacity(0.4), lineWidth: 1)
                                }
                            }
                    }
                    .scaleEffect(voice.isRecording ? 1.08 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: voice.isRecording)
            }
            .buttonStyle(PressButtonStyle())
            .padding(.leading, 8)
            .padding(.bottom, 7)
            .disabled(vm.isGenerating)

            TextField("Сообщение...", text: $bvm.inputText, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(Color.txt1)
                .tint(Color.violet)
                .lineLimit(1...6)
                .padding(.horizontal, 4)
                .padding(.vertical, 12)
                .disabled(vm.isGenerating)

            if vm.isGenerating {
                Button { vm.stopGeneration() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(PressButtonStyle())
                .padding(.trailing, 6)
                .padding(.bottom, 6)
                .transition(.scale.combined(with: .opacity))
            } else {
                Button { vm.send() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background {
                            Circle().fill(canSend
                                ? AnyShapeStyle(Color.violet)
                                : AnyShapeStyle(Color.white.opacity(0.08)))
                        }
                        .glow(canSend ? Color.violet : .clear, radius: 10)
                }
                .buttonStyle(PressButtonStyle())
                .disabled(!canSend)
                .padding(.trailing, 6)
                .padding(.bottom, 6)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            voice.isRecording
                                ? AnyShapeStyle(Color.violet.opacity(0.5))
                                : vm.isGenerating
                                    ? AnyShapeStyle(Color.violet.opacity(0.4))
                                    : AnyShapeStyle(Color.borderHi),
                            lineWidth: 1
                        )
                }
                .shadow(color: (vm.isGenerating || voice.isRecording) ? Color.violet.opacity(0.25) : .clear, radius: 20)
        }
        .animation(.easeInOut(duration: 0.4), value: vm.isGenerating)
        .animation(.easeInOut(duration: 0.3), value: voice.isRecording)
    }

    private var canSend: Bool {
        !vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty && vm.selectedModel != nil && !vm.isGenerating
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(ChatViewModel.self) private var vm
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        presetSection
                        if vm.currentConversation != nil {
                            exportSection
                        }
                    }
                    .padding(16)
                    .padding(.top, 8)
                }
            }
            .navigationTitle("Настройки")
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

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Режим ассистента")
            VStack(spacing: 8) {
                ForEach(SystemPromptPreset.allCases, id: \.rawValue) { preset in
                    presetRow(preset)
                }
            }
        }
    }

    private func presetRow(_ preset: SystemPromptPreset) -> some View {
        let isSelected = vm.promptPreset == preset
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            vm.promptPreset = preset
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.violet.opacity(0.20) : Color.white.opacity(0.05))
                        .frame(width: 40, height: 40)
                    Image(systemName: preset.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.violet : Color.txt3)
                }
                Text(preset.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? Color.txt1 : Color.txt2)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.violet)
                        .glow(Color.violet, radius: 5)
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.violet.opacity(0.4) : Color.borderHi,
                                lineWidth: isSelected ? 1 : 0.5
                            )
                    }
            }
        }
        .buttonStyle(PressButtonStyle())
        .animation(.spring(response: 0.3), value: isSelected)
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Экспорт")
            ShareLink(
                item: vm.exportText,
                subject: Text(vm.currentConversation?.title ?? "Диалог"),
                message: Text("Экспортировано из LocalAI")
            ) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.violet.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.violet)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Поделиться диалогом")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.txt1)
                        Text(vm.currentConversation?.title ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.txt3)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.txt3)
                }
                .padding(14)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.borderHi, lineWidth: 0.5)
                        }
                }
            }
            .buttonStyle(PressButtonStyle())
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.txt3)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, 4)
    }
}

// MARK: - Edit Message Sheet

private struct EditMessageSheet: View {
    let message: ChatMessage
    let onSave: (String) -> Void

    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(message: ChatMessage, onSave: @escaping (String) -> Void) {
        self.message = message
        self.onSave = onSave
        _text = State(initialValue: message.content)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bg.ignoresSafeArea()
                TextEditor(text: $text)
                    .font(.system(size: 16))
                    .foregroundStyle(Color.txt1)
                    .tint(Color.violet)
                    .scrollContentBackground(.hidden)
                    .padding(16)
            }
            .navigationTitle("Редактировать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(Color.txt2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Отправить") {
                        onSave(text)
                    }
                    .foregroundStyle(Color.violet)
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
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
                                    .background(Color.violet, in: Capsule())
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
    var isLastAI: Bool = false
    var onRegenerate: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    private var isUser: Bool { message.role == .user }
    @State private var appeared = false

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
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
                    Group {
                        if isUser {
                            Text(message.content)
                                .font(.system(size: 16))
                                .foregroundStyle(Color.white)
                        } else {
                            MarkdownText(content: message.content)
                        }
                    }
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

                        if isUser, let edit = onEdit {
                            Button(action: edit) {
                                Label("Редактировать", systemImage: "pencil")
                            }
                        }

                        if isLastAI, let regen = onRegenerate {
                            Button(action: regen) {
                                Label("Повторить", systemImage: "arrow.clockwise")
                            }
                        }
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

            // Regenerate button below last AI message
            if isLastAI, let regen = onRegenerate {
                Button(action: regen) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Повторить")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Color.txt3)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.05), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.borderHi, lineWidth: 0.5))
                }
                .buttonStyle(PressButtonStyle())
                .padding(.leading, 38)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
            }
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

// MARK: - Markdown renderer

struct MarkdownText: View {
    let content: String

    private struct Block: Identifiable {
        let id = UUID()
        enum Kind { case prose(String), code(lang: String, body: String) }
        let kind: Kind
    }

    private var blocks: [Block] {
        var result: [Block] = []
        var inCode = false
        var codeLang = ""
        var codeLines: [String] = []
        var proseLines: [String] = []

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode {
                    result.append(Block(kind: .code(lang: codeLang, body: codeLines.joined(separator: "\n"))))
                    codeLines = []; inCode = false
                } else {
                    if !proseLines.isEmpty {
                        result.append(Block(kind: .prose(proseLines.joined(separator: "\n"))))
                        proseLines = []
                    }
                    codeLang = String(line.dropFirst(3)); inCode = true
                }
            } else if inCode {
                codeLines.append(line)
            } else {
                proseLines.append(line)
            }
        }
        if inCode && !codeLines.isEmpty {
            result.append(Block(kind: .code(lang: codeLang, body: codeLines.joined(separator: "\n"))))
        } else if !proseLines.isEmpty {
            result.append(Block(kind: .prose(proseLines.joined(separator: "\n"))))
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(blocks) { block in
                switch block.kind {
                case .prose(let text):
                    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                    let attr = (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
                    Text(attr)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.txt1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let lang, let body):
                    CodeBlock(lang: lang, code: body)
                }
            }
        }
    }
}

// MARK: - Code block with copy button

private struct CodeBlock: View {
    let lang: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack {
                if !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.txt3)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text(copied ? "Скопировано" : "Копировать")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(copied ? Color.violet : Color.txt3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(copied ? Color.violet.opacity(0.12) : Color.white.opacity(0.05))
                    )
                }
                .buttonStyle(PressButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.txt2)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(copied ? Color.violet.opacity(0.3) : Color.borderHi, lineWidth: 0.5)
        }
        .animation(.easeOut(duration: 0.2), value: copied)
    }
}
