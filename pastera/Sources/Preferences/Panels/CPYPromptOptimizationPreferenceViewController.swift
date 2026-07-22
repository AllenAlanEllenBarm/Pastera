import AppKit

@MainActor
final class CPYPromptOptimizationPreferenceViewController: PasteraPreferencePageViewController {
    private let settingsStore: any PromptOptimizationSettingsStoring
    private let apiKeyStore: any PromptOptimizationAPIKeyStoring
    private let optimizationService: any PromptOptimizationServicing
    private weak var promptOptimizationSection: PromptOptimizationPreferenceSection?

    init(
        settingsStore: any PromptOptimizationSettingsStoring = PromptOptimizationSettingsStore(),
        apiKeyStore: any PromptOptimizationAPIKeyStoring = PromptOptimizationAPIKeyStore(),
        optimizationService: any PromptOptimizationServicing = AppEnvironment.current.promptOptimizationService
    ) {
        self.settingsStore = settingsStore
        self.apiKeyStore = apiKeyStore
        self.optimizationService = optimizationService
        super.init(
            paneID: .promptOptimization,
            title: pasteraScriptString("Prompt Optimization", "提示词优化")
        )
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        super.loadView()
        let section = PromptOptimizationPreferenceSection(
            settingsStore: settingsStore,
            apiKeyStore: apiKeyStore,
            optimizationService: optimizationService
        )
        section.onContentSizeChange = { [weak self] in
            self?.invalidateContentSize()
        }
        promptOptimizationSection = section
        addAdaptiveContent(section)
        registerAnchor("promptOptimization.configuration", view: section)
        invalidateContentSize()
    }

    var promptOptimizationSectionForTesting: PromptOptimizationPreferenceSection? {
        promptOptimizationSection
    }
}
