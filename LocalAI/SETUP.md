# Настройка проекта в Xcode

## 1. Создать проект

1. Xcode → File → New → Project
2. iOS → App → Next
3. Product Name: **LocalAI**
4. Interface: **SwiftUI**
5. Language: **Swift**
6. Сохранить в папку `/Users/gostheres/Desktop/local ai/LocalAI/`
7. **Удалить** автоматически созданные ContentView.swift и LocalAIApp.swift (заменим своими)

## 2. Добавить исходники

Перетащить в проект (убедись что галочка "Copy if needed" стоит):
```
LocalAI/
├── LocalAIApp.swift
├── ContentView.swift
├── Models/
│   ├── AIModel.swift
│   └── ChatMessage.swift
├── ViewModels/
│   ├── ModelLibraryViewModel.swift
│   ├── ChatViewModel.swift
│   └── InferenceService.swift
└── Views/
    ├── ModelLibraryView.swift
    └── ChatView.swift
```

## 3. Добавить MLX через Swift Package Manager

File → Add Package Dependencies → вставить URL:

```
https://github.com/ml-explore/mlx-swift-examples
```

Выбрать **Up to Next Major Version** от `0.21.0`.

Добавить в таргет следующие продукты:
- `MLXLLM`
- `MLXLMCommon`
- `MLX`

## 4. Entitlements (обязательно!)

В файле `LocalAI.entitlements` добавить:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

Это нужно **только для первого скачивания** моделей с HuggingFace.
После загрузки всё работает полностью офлайн.

Также для больших моделей добавить:
```xml
<key>com.apple.developer.kernel.increased-memory-limit</key>
<true/>
```

## 5. Info.plist

Добавить ключ для использования сети:
```
Privacy - Local Network Usage Description
```
Значение: `Требуется для первоначальной загрузки моделей`

## 6. Сборка

- Выбрать целевое устройство (реальный iPhone, не симулятор — симулятор не поддерживает MLX)
- Cmd+R

## Где хранятся модели

Модели кэшируются автоматически в:
```
~/Library/Caches/huggingface/
```

Занимают место согласно размерам в каталоге моделей.
