# LLM GOD

Run large language models completely offline on your iPhone. No server, no API key, no internet after the first download.

Built with SwiftUI and Apple's MLX framework.

![iOS 17+](https://img.shields.io/badge/iOS-17%2B-black) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![MLX](https://img.shields.io/badge/MLX-Swift-blue)

## What it does

- Runs 4-bit quantized LLMs directly on iPhone using the Neural Engine / GPU
- Downloads models once from HuggingFace, then works fully offline
- Keeps conversation history on-device (UserDefaults, no cloud sync)
- Shows inference speed in tokens/sec

## Models

| Model | Size | Context | Notes |
|---|---|---|---|
| Phi-3.5 Mini | 2.2 GB | 128k | Fast, good reasoning |
| Gemma 3 4B | 2.5 GB | 8k | Great for dialogue |
| Mistral 7B | 4.1 GB | 32k | GPT-3.5 level |
| Qwen 2.5 7B | 4.5 GB | 32k | Best overall |

Recommended device: iPhone 15 Pro or later (8GB RAM). Older devices can run the smaller models.

## Stack

- **SwiftUI** — UI
- **MLX Swift** — on-device inference via Apple Silicon
- **mlx-swift-lm** — model loading and chat session management
- **HuggingFace Hub** — model distribution

## Building

Requirements: Xcode 15+, real iPhone (MLX doesn't run on Simulator)

```bash
# Generate Xcode project
brew install xcodegen
xcodegen generate --spec project.yml

# Open and build
open LocalAI.xcodeproj
```

SPM dependencies resolve automatically on first build (~a few minutes).

## Install without App Store

Build and archive in Xcode, then install via [Sideloadly](https://sideloadly.io) with a free Apple ID.

## Notes

- First launch requires internet to download the model (~2-4 GB)
- After that, everything runs offline
- Models are cached in `~/Library/Caches/huggingface/`
- Long-press a model card to delete it and free up space
