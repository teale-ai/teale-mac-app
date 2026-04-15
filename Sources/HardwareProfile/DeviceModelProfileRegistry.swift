import Foundation
import SharedTypes

// MARK: - Device Model Profile Registry

/// Curated profiles mapping (device class, model) → optimal llama.cpp parameters.
/// Profiles are ordered by specificity: model-specific entries override device-class defaults.
public struct DeviceModelProfileRegistry: Sendable {

    // MARK: - Built-in Profiles

    public static let profiles: [DeviceModelProfile] = [

        // ════════════════════════════════════════════════════════════════════
        // Ultra Desktop (M*Ultra, 64-192 GB) — maximize quality and throughput
        // ════════════════════════════════════════════════════════════════════

        DeviceModelProfile(
            deviceClass: .ultraDesktop,
            params: InferenceProfile(
                contextSize: 65536,
                kvCacheType: "q8_0",
                batchSize: 4096,
                flashAttn: true,
                mmap: true,
                parallelSlots: 4,
                gpuLayers: 999
            ),
            notes: "Ultra desktop default — full quality, high throughput"
        ),

        // Llama 4 Scout 109B on Ultra: still memory-heavy, dial back context
        DeviceModelProfile(
            deviceClass: .ultraDesktop,
            modelID: "llama-4-scout-17b-16e-instruct-4bit",
            minRAMGB: 72,
            params: InferenceProfile(
                contextSize: 32768,
                kvCacheType: "q4_0",
                batchSize: 2048,
                parallelSlots: 2
            ),
            notes: "109B MoE needs memory headroom even on Ultra"
        ),

        // Qwen models on Ultra: disable reasoning by default
        DeviceModelProfile(
            deviceClass: .ultraDesktop,
            modelFamily: "Qwen",
            params: InferenceProfile(
                reasoningOff: true
            ),
            notes: "Qwen3 thinking mode consumes tokens rapidly; disable by default"
        ),

        // ════════════════════════════════════════════════════════════════════
        // Max Desktop (M*Max, 32-128 GB) — high-end, slightly constrained
        // ════════════════════════════════════════════════════════════════════

        DeviceModelProfile(
            deviceClass: .maxDesktop,
            minRAMGB: 48,
            params: InferenceProfile(
                contextSize: 32768,
                kvCacheType: "q8_0",
                batchSize: 2048,
                flashAttn: true,
                mmap: true,
                parallelSlots: 2,
                gpuLayers: 999
            ),
            notes: "Max desktop 48GB+ — full offload, good throughput"
        ),

        DeviceModelProfile(
            deviceClass: .maxDesktop,
            maxRAMGB: 48,
            params: InferenceProfile(
                contextSize: 16384,
                kvCacheType: "q4_0",
                batchSize: 1024,
                flashAttn: true,
                mmap: true,
                parallelSlots: 1,
                gpuLayers: 999
            ),
            notes: "Max desktop 32GB — tighter memory, single slot"
        ),

        // Large models on Max 32GB: aggressive memory saving
        DeviceModelProfile(
            deviceClass: .maxDesktop,
            modelFamily: "Qwen",
            maxRAMGB: 48,
            params: InferenceProfile(
                contextSize: 8192,
                kvCacheType: "q4_0",
                reasoningOff: true
            ),
            notes: "Qwen 32B on 32GB Max — minimal context to fit"
        ),

        DeviceModelProfile(
            deviceClass: .maxDesktop,
            modelFamily: "Qwen",
            minRAMGB: 48,
            params: InferenceProfile(
                reasoningOff: true
            ),
            notes: "Qwen on 48GB+ Max — default settings, reasoning off"
        ),

        // ════════════════════════════════════════════════════════════════════
        // Pro Laptop (M*Pro, 16-48 GB) — mainstream power user
        // ════════════════════════════════════════════════════════════════════

        DeviceModelProfile(
            deviceClass: .proLaptop,
            minRAMGB: 32,
            params: InferenceProfile(
                contextSize: 32768,
                kvCacheType: "q8_0",
                batchSize: 2048,
                flashAttn: true,
                mmap: true,
                parallelSlots: 1,
                gpuLayers: 999
            ),
            notes: "Pro 32GB+ — good context, single slot to conserve memory"
        ),

        DeviceModelProfile(
            deviceClass: .proLaptop,
            maxRAMGB: 32,
            params: InferenceProfile(
                contextSize: 16384,
                kvCacheType: "q4_0",
                batchSize: 1024,
                flashAttn: true,
                mmap: false,
                parallelSlots: 1,
                gpuLayers: 999
            ),
            notes: "Pro 16-18GB — constrained, q4 KV cache"
        ),

        // 8B models on Pro 16GB fit well, can afford more context
        DeviceModelProfile(
            deviceClass: .proLaptop,
            modelID: "llama-3.1-8b-instruct-4bit",
            maxRAMGB: 32,
            params: InferenceProfile(
                contextSize: 32768,
                kvCacheType: "q4_0"
            ),
            notes: "8B Llama on 16GB Pro — small enough for 32K context"
        ),

        DeviceModelProfile(
            deviceClass: .proLaptop,
            modelID: "qwen3-8b-4bit",
            maxRAMGB: 32,
            params: InferenceProfile(
                contextSize: 32768,
                kvCacheType: "q4_0",
                reasoningOff: true
            ),
            notes: "8B Qwen on 16GB Pro — fits 32K with q4 KV"
        ),

        DeviceModelProfile(
            deviceClass: .proLaptop,
            modelFamily: "Qwen",
            minRAMGB: 32,
            params: InferenceProfile(
                reasoningOff: true
            ),
            notes: "Qwen on 32GB+ Pro — reasoning off by default"
        ),

        // ════════════════════════════════════════════════════════════════════
        // Base Mac (M1/M2/M3/M4 base, 8-24 GB) — memory-constrained
        // ════════════════════════════════════════════════════════════════════

        DeviceModelProfile(
            deviceClass: .baseMac,
            minRAMGB: 16,
            params: InferenceProfile(
                contextSize: 16384,
                kvCacheType: "q4_0",
                batchSize: 1024,
                flashAttn: false,
                mmap: false,
                parallelSlots: 1,
                gpuLayers: 999
            ),
            notes: "Base Mac 16-24GB — moderate context, q4 KV to conserve memory"
        ),

        DeviceModelProfile(
            deviceClass: .baseMac,
            maxRAMGB: 16,
            params: InferenceProfile(
                contextSize: 4096,
                kvCacheType: "q4_0",
                batchSize: 512,
                flashAttn: false,
                mmap: false,
                parallelSlots: 1,
                gpuLayers: 999
            ),
            notes: "Base Mac 8GB — minimal context, smallest models only"
        ),

        // M3/M4 base can use flash attention (hardware support)
        DeviceModelProfile(
            deviceClass: .baseMac,
            minRAMGB: 16,
            params: InferenceProfile(
                flashAttn: true
            ),
            notes: "Override: M3/M4 base chips support flash attention well"
            // Note: resolver checks chip generation >= 3 before applying this
        ),

        // Small models on 16GB base Mac can afford more context
        DeviceModelProfile(
            deviceClass: .baseMac,
            modelID: "llama-3.2-1b-instruct-4bit",
            minRAMGB: 16,
            params: InferenceProfile(
                contextSize: 32768
            ),
            notes: "1B model on 16GB — tiny model, plenty of room for context"
        ),

        DeviceModelProfile(
            deviceClass: .baseMac,
            modelID: "llama-3.2-3b-instruct-4bit",
            minRAMGB: 16,
            params: InferenceProfile(
                contextSize: 16384
            ),
            notes: "3B model on 16GB — still small enough for decent context"
        ),

        DeviceModelProfile(
            deviceClass: .baseMac,
            modelFamily: "Qwen",
            params: InferenceProfile(
                reasoningOff: true
            ),
            notes: "Qwen on base Mac — always disable reasoning"
        ),

        // ════════════════════════════════════════════════════════════════════
        // Mobile (A-series, 4-16 GB) — very constrained
        // ════════════════════════════════════════════════════════════════════

        DeviceModelProfile(
            deviceClass: .mobile,
            params: InferenceProfile(
                contextSize: 4096,
                kvCacheType: "q4_0",
                batchSize: 256,
                flashAttn: false,
                mmap: false,
                parallelSlots: 1,
                gpuLayers: 999
            ),
            notes: "Mobile default — minimal everything"
        ),

        // ════════════════════════════════════════════════════════════════════
        // Other (NVIDIA, AMD, Intel, ARM) — conservative defaults
        // ════════════════════════════════════════════════════════════════════

        DeviceModelProfile(
            deviceClass: .other,
            params: InferenceProfile(
                contextSize: 8192,
                kvCacheType: "q8_0",
                batchSize: 1024,
                flashAttn: false,
                mmap: true,
                parallelSlots: 1,
                gpuLayers: 999
            ),
            notes: "Non-Apple default — conservative, mmap for large models"
        ),
    ]
}
