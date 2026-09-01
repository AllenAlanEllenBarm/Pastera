import Foundation

enum PromptOptimizationModelChoice: Equatable {
    case automaticFree
    case remoteProfile(UUID)
}

struct PromptOptimizationRemoteProfileDraft {
    private(set) var settings: PromptOptimizationSettings
    private(set) var selectedProfileID: UUID
    private var persistedProfileIDs: Set<UUID>

    init(settings: PromptOptimizationSettings) {
        var repaired = settings
        repaired.repairActiveRemoteProfile()
        self.settings = repaired
        self.selectedProfileID = repaired.activeRemoteProfileID
        self.persistedProfileIDs = Set(repaired.remoteProfiles.map(\.id))
    }

    var selectedProfile: PromptOptimizationRemoteProfile? {
        settings.remoteProfiles.first { $0.id == selectedProfileID }
    }

    var selectedModelChoice: PromptOptimizationModelChoice {
        switch settings.provider {
        case .automaticFree:
            return .automaticFree
        case .openAICompatible:
            return .remoteProfile(selectedProfileID)
        }
    }

    func isPersisted(_ profileID: UUID) -> Bool {
        persistedProfileIDs.contains(profileID)
    }

    mutating func markSaved() {
        persistedProfileIDs = Set(settings.remoteProfiles.map(\.id))
    }

    mutating func selectModelChoice(_ choice: PromptOptimizationModelChoice) {
        switch choice {
        case .automaticFree:
            settings.provider = .automaticFree
        case let .remoteProfile(profileID):
            guard settings.remoteProfiles.contains(where: { $0.id == profileID }) else { return }
            settings.provider = .openAICompatible
            selectedProfileID = profileID
        }
    }

    mutating func confirmRemoteOrigin(_ origin: String) {
        settings.confirmedOrigins.insert(origin)
    }

    mutating func selectProfile(id: UUID) {
        guard settings.remoteProfiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
    }

    mutating func updateSelected(
        displayName: String,
        preset: OpenAICompatiblePreset,
        baseURL: String,
        model: String,
        allowsInsecureHTTP: Bool
    ) {
        guard let index = settings.remoteProfiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return
        }
        settings.remoteProfiles[index].displayName = displayName
        settings.remoteProfiles[index].preset = preset
        settings.remoteProfiles[index].baseURL = baseURL
        settings.remoteProfiles[index].model = model
        settings.remoteProfiles[index].allowsInsecureHTTP = allowsInsecureHTTP
    }

    mutating func addProfile(preset: OpenAICompatiblePreset, id: UUID) -> UUID {
        let displayName = uniqueDisplayName(for: preset.defaultProfileName)
        settings.remoteProfiles.append(.makeDefault(id: id, preset: preset, displayName: displayName))
        selectedProfileID = id
        return id
    }

    mutating func applyPresetDefaults() {
        guard let index = settings.remoteProfiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return
        }
        let preset = settings.remoteProfiles[index].preset
        settings.remoteProfiles[index].baseURL = preset.defaultBaseURL
        settings.remoteProfiles[index].model = preset.defaultModel
        settings.remoteProfiles[index].allowsInsecureHTTP = false
    }

    mutating func removeOrResetSelectedProfile() {
        guard let index = settings.remoteProfiles.firstIndex(where: { $0.id == selectedProfileID }) else {
            return
        }
        if settings.remoteProfiles.count == 1 {
            settings.remoteProfiles[index] = .makeDefault(id: selectedProfileID)
            return
        }
        settings.remoteProfiles.remove(at: index)
        selectedProfileID = settings.remoteProfiles[0].id
    }

    func snapshot() -> PromptOptimizationSettings {
        var snapshot = settings
        snapshot.activeRemoteProfileID = selectedProfileID
        return snapshot
    }

    private func uniqueDisplayName(for baseName: String) -> String {
        let existingNames = Set(settings.remoteProfiles.map { $0.displayName.lowercased() })
        guard existingNames.contains(baseName.lowercased()) else { return baseName }
        var suffix = 2
        while existingNames.contains("\(baseName) \(suffix)".lowercased()) {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }
}
