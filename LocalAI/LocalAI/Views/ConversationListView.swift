import SwiftUI

struct ConversationListView: View {
    @Environment(ChatViewModel.self) private var vm
    @Environment(ModelLibraryViewModel.self) private var libraryVM
    @Binding var isPresented: Bool

    @State private var renamingId: UUID?
    @State private var renameText: String = ""
    @State private var searchText: String = ""

    private var filteredConversations: [Conversation] {
        if searchText.isEmpty { return vm.conversations }
        return vm.conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.preview.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredConversations.isEmpty {
                    emptyState
                } else {
                    ForEach(filteredConversations) { conv in
                        ConversationRow(
                            conv: conv,
                            isActive: vm.currentConversation?.id == conv.id,
                            isRenaming: renamingId == conv.id,
                            renameText: $renameText
                        ) {
                            vm.selectConversation(conv)
                            isPresented = false
                        } onRename: {
                            renamingId = conv.id
                            renameText = conv.title
                        } onRenameCommit: {
                            vm.renameConversation(conv, to: renameText)
                            renamingId = nil
                        } onDelete: {
                            vm.deleteConversation(conv)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: "Поиск по диалогам")
            .navigationTitle("История")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Закрыть") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    modelPickerMenu
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "Нет истории чатов" : "Ничего не найдено")
                .font(.headline)
            Text(searchText.isEmpty ? "Выберите модель и начните разговор" : "Попробуйте другой запрос")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var modelPickerMenu: some View {
        Menu {
            ForEach(libraryVM.downloadedModels) { model in
                Button {
                    vm.selectedModel = model
                    vm.newConversation(model: model)
                    isPresented = false
                } label: {
                    Label(model.name, systemImage: model.iconName)
                }
            }
            if libraryVM.downloadedModels.isEmpty {
                Text("Нет загруженных моделей")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .font(.title3)
        }
    }
}

private struct ConversationRow: View {
    let conv: Conversation
    let isActive: Bool
    let isRenaming: Bool
    @Binding var renameText: String
    let onSelect: () -> Void
    let onRename: () -> Void
    let onRenameCommit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 3, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    if isRenaming {
                        TextField("Название", text: $renameText)
                            .font(.headline)
                            .onSubmit { onRenameCommit() }
                            .submitLabel(.done)
                    } else {
                        Text(conv.title)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Text(conv.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(conv.updatedAt.formatted(.relative(presentation: .numeric)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button(action: onRename) {
                Label("Переименовать", systemImage: "pencil")
            }
            .tint(.orange)
        }
    }
}
