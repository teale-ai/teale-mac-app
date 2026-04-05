import Foundation
import SharedTypes

// MARK: - Model Catalog

public struct ModelCatalog: Sendable {
    public init() {}

    /// Curated list of recommended models
    public static let allModels: [ModelDescriptor] = [
        // Small models — run on any Apple Silicon Mac
        ModelDescriptor(
            id: "llama-3.2-1b-instruct-4bit",
            name: "Llama 3.2 1B Instruct",
            huggingFaceRepo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            parameterCount: "1B",
            quantization: .q4,
            estimatedSizeGB: 0.7,
            requiredRAMGB: 4.0,
            family: "Llama",
            description: "Fast, lightweight model for basic tasks"
        ),
        ModelDescriptor(
            id: "llama-3.2-3b-instruct-4bit",
            name: "Llama 3.2 3B Instruct",
            huggingFaceRepo: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            parameterCount: "3B",
            quantization: .q4,
            estimatedSizeGB: 1.8,
            requiredRAMGB: 6.0,
            family: "Llama",
            description: "Good balance of speed and quality for small tasks"
        ),
        ModelDescriptor(
            id: "gemma-2-2b-it-4bit",
            name: "Gemma 2 2B Instruct",
            huggingFaceRepo: "mlx-community/gemma-2-2b-it-4bit",
            parameterCount: "2B",
            quantization: .q4,
            estimatedSizeGB: 1.4,
            requiredRAMGB: 5.0,
            family: "Gemma",
            description: "Google's efficient small model"
        ),

        // Medium models — 16GB+ RAM
        ModelDescriptor(
            id: "llama-3.1-8b-instruct-4bit",
            name: "Llama 3.1 8B Instruct",
            huggingFaceRepo: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            parameterCount: "8B",
            quantization: .q4,
            estimatedSizeGB: 4.5,
            requiredRAMGB: 10.0,
            family: "Llama",
            description: "Strong general-purpose model"
        ),
        ModelDescriptor(
            id: "qwen2.5-7b-instruct-4bit",
            name: "Qwen 2.5 7B Instruct",
            huggingFaceRepo: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            parameterCount: "7B",
            quantization: .q4,
            estimatedSizeGB: 4.2,
            requiredRAMGB: 10.0,
            family: "Qwen",
            description: "Excellent multilingual and coding model"
        ),
        ModelDescriptor(
            id: "mistral-7b-instruct-v0.3-4bit",
            name: "Mistral 7B Instruct v0.3",
            huggingFaceRepo: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            parameterCount: "7B",
            quantization: .q4,
            estimatedSizeGB: 4.1,
            requiredRAMGB: 10.0,
            family: "Mistral",
            description: "Fast and capable instruction-following model"
        ),
        ModelDescriptor(
            id: "phi-4-4bit",
            name: "Phi 4",
            huggingFaceRepo: "mlx-community/phi-4-4bit",
            parameterCount: "14B",
            quantization: .q4,
            estimatedSizeGB: 8.0,
            requiredRAMGB: 14.0,
            family: "Phi",
            description: "Microsoft's strong reasoning model"
        ),

        // Large models — 32GB+ RAM
        ModelDescriptor(
            id: "qwen2.5-32b-instruct-4bit",
            name: "Qwen 2.5 32B Instruct",
            huggingFaceRepo: "mlx-community/Qwen2.5-32B-Instruct-4bit",
            parameterCount: "32B",
            quantization: .q4,
            estimatedSizeGB: 18.0,
            requiredRAMGB: 28.0,
            family: "Qwen",
            description: "High-quality model for complex tasks"
        ),

        // XL models — 64GB+ RAM
        ModelDescriptor(
            id: "llama-3.1-70b-instruct-4bit",
            name: "Llama 3.1 70B Instruct",
            huggingFaceRepo: "mlx-community/Meta-Llama-3.1-70B-Instruct-4bit",
            parameterCount: "70B",
            quantization: .q4,
            estimatedSizeGB: 38.0,
            requiredRAMGB: 52.0,
            family: "Llama",
            description: "Frontier-class model, excellent at everything"
        ),
    ]

    /// Filter models that can run on the given hardware
    public func availableModels(for hardware: HardwareCapability) -> [ModelDescriptor] {
        ModelCatalog.allModels.filter { model in
            hardware.availableRAMForModelsGB >= model.requiredRAMGB
        }
    }
}
