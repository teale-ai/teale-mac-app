import SwiftUI
import SharedTypes

struct ModelBrowserView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText: String = ""
    @State private var switchConfirmModel: ModelDescriptor?

    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(appState.loc("models.search"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quaternary)

            Divider()

            // Model list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filteredModels) { model in
                        ModelRowView(
                            model: model,
                            onSwitchRequest: { switchConfirmModel = $0 }
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                }
            }

            Divider()

            // Footer with cache info
            HStack {
                Text(String(format: appState.loc("models.available"), appState.modelManager.compatibleModels.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: appState.loc("models.gbAvailable"), Int(appState.hardware.availableRAMForModelsGB)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
        }
        .navigationTitle(appState.loc("models.title"))
        .alert(appState.loc("models.switchModel"), isPresented: Binding(
            get: { switchConfirmModel != nil },
            set: { if !$0 { switchConfirmModel = nil } }
        )) {
            Button(appState.loc("models.cancel"), role: .cancel) {
                switchConfirmModel = nil
            }
            Button(appState.loc("models.switchButton")) {
                if let model = switchConfirmModel {
                    switchConfirmModel = nil
                    Task { await appState.loadModel(model) }
                }
            }
        } message: {
            if let model = switchConfirmModel {
                Text(String(format: appState.loc("models.switchConfirm"), model.name))
            }
        }
        .alert(appState.loc("models.downloadComplete"), isPresented: Binding(
            get: { appState.justDownloadedModel != nil },
            set: { if !$0 { appState.justDownloadedModel = nil } }
        )) {
            Button(appState.loc("models.notNow"), role: .cancel) {
                appState.justDownloadedModel = nil
            }
            Button(appState.loc("models.load")) {
                if let model = appState.justDownloadedModel {
                    appState.justDownloadedModel = nil
                    Task { await appState.loadModel(model) }
                }
            }
        } message: {
            if let model = appState.justDownloadedModel {
                Text(String(format: appState.loc("models.readyToLoad"), model.name))
            }
        }
    }

    private var filteredModels: [ModelDescriptor] {
        let models = appState.modelManager.compatibleModels
        if searchText.isEmpty { return models }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.family.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Model Row

struct ModelRowView: View {
    @Environment(AppState.self) private var appState
    let model: ModelDescriptor
    var onSwitchRequest: (ModelDescriptor) -> Void
    @State private var error: String?

    private var isDownloaded: Bool {
        appState.downloadedModelIDs.contains(model.id)
    }

    private var isDownloading: Bool {
        appState.activeDownloads[model.id] != nil
    }

    private var downloadProgress: Double? {
        appState.activeDownloads[model.id]
    }

    private var isCurrentlyLoaded: Bool {
        if case .ready(let loaded) = appState.engineStatus {
            return loaded.id == model.id
        }
        return false
    }

    private var isCurrentlyLoading: Bool {
        if case .loadingModel(let loading) = appState.engineStatus {
            return loading.id == model.id
        }
        return false
    }

    /// Another model is currently loaded (not this one)
    private var hasOtherModelLoaded: Bool {
        if case .ready(let loaded) = appState.engineStatus {
            return loaded.id != model.id
        }
        return false
    }

    /// Engine is busy loading or generating
    private var isEngineOccupied: Bool {
        switch appState.engineStatus {
        case .loadingModel, .generating: return true
        default: return false
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Model info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.body.bold())
                    statusBadge
                }

                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(model.parameterCount, systemImage: "cpu")
                    Label(model.quantization.displayName, systemImage: "slider.horizontal.3")
                    Label(String(format: "%.1f GB", model.estimatedSizeGB), systemImage: "externaldrive")
                    Label(String(format: "%.0f GB RAM", model.requiredRAMGB), systemImage: "memorychip")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Spacer()

            // Actions
            actionView
        }

        if let error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        if isCurrentlyLoaded {
            badge(appState.loc("models.loaded"), color: .green)
        } else if isCurrentlyLoading {
            let phase = appState.loadingPhase.lowercased()
            if phase.contains("verif") {
                badge(appState.loc("models.checking"), color: .yellow)
            } else {
                badge(appState.loc("models.loading"), color: .blue)
            }
        } else if isDownloading {
            badge(appState.loc("models.downloading"), color: .orange)
        } else if isDownloaded {
            badge(appState.loc("models.ready"), color: .secondary)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionView: some View {
        if isCurrentlyLoaded {
            // Loaded — offer unload
            Button(appState.loc("models.unload")) {
                Task { await appState.unloadModel() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        } else if isCurrentlyLoading {
            // Loading weights into GPU
            VStack(alignment: .trailing, spacing: 3) {
                let phase = appState.loadingPhase.lowercased()
                let isWeightLoading = phase.contains("loading") || phase.contains("warming")
                if let progress = appState.loadingProgress,
                   progress > 0 && progress < 1.0 && !isWeightLoading {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                    Text(appState.loadingPhase.isEmpty ? appState.loc("models.preparing") : appState.loadingPhase)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 90)

        } else if isDownloading {
            // Downloading files — show progress
            VStack(alignment: .trailing, spacing: 3) {
                if let progress = downloadProgress, progress > 0 && progress < 1.0 {
                    ProgressView(value: progress)
                        .frame(width: 80)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(minWidth: 90)

        } else if isDownloaded {
            // On disk — load into memory
            Button(appState.loc("models.load")) {
                if hasOtherModelLoaded || isEngineOccupied {
                    onSwitchRequest(model)
                } else {
                    Task {
                        error = nil
                        await appState.loadModel(model)
                        if case .error(let msg) = appState.engineStatus {
                            error = msg
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        } else {
            // Not downloaded — download only (no alert, no load)
            Button {
                Task {
                    error = nil
                    await appState.downloadModel(model)
                }
            } label: {
                Label(appState.loc("models.download"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
