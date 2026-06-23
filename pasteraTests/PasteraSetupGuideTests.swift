//
//  PasteraSetupGuideTests.swift
//
//  Pastera
//
//  Created by Codex on 2026/06/22.
//

import Foundation
import Testing
@testable import Pastera

struct PasteraSetupGuideTests {
    @Test
    func authorizedLaunchDoesNotShowSetupGuide() {
        let policy = PasteraSetupGuidePolicy(
            arguments: [],
            isAccessibilityTrusted: true,
            isAutomaticPasteEnabled: false,
            didDismissSetupGuide: false
        )

        #expect(!policy.shouldShowSetupGuide)
    }

    @Test
    func installerLaunchArgumentForcesSetupGuide() {
        let policy = PasteraSetupGuidePolicy(
            arguments: ["Pastera", "--pastera-open-setup-guide"],
            isAccessibilityTrusted: true,
            isAutomaticPasteEnabled: false,
            didDismissSetupGuide: true
        )

        #expect(policy.shouldShowSetupGuide)
    }

    @Test
    func unauthorizedLaunchDoesNotShowSetupGuideWhenAutomaticPasteIsDisabled() {
        let policy = PasteraSetupGuidePolicy(
            arguments: [],
            isAccessibilityTrusted: false,
            isAutomaticPasteEnabled: false,
            didDismissSetupGuide: false
        )

        #expect(!policy.shouldShowSetupGuide)
    }

    @Test
    func unauthorizedLaunchShowsSetupGuideWhenAutomaticPasteIsEnabled() {
        let policy = PasteraSetupGuidePolicy(
            arguments: [],
            isAccessibilityTrusted: false,
            isAutomaticPasteEnabled: true,
            didDismissSetupGuide: false
        )

        #expect(policy.shouldShowSetupGuide)
    }

    @Test
    func dismissedSetupGuideDoesNotBlockNormalLaunch() {
        let policy = PasteraSetupGuidePolicy(
            arguments: [],
            isAccessibilityTrusted: false,
            isAutomaticPasteEnabled: true,
            didDismissSetupGuide: true
        )

        #expect(!policy.shouldShowSetupGuide)
    }

    @Test
    func unauthorizedGuideOnlyShowsOpenSettingsActionBeforeSettingsAreOpened() {
        let viewState = PasteraSetupGuideViewState(
            isAccessibilityTrusted: false,
            didOpenAccessibilitySettings: false
        )

        #expect(viewState.availableActions == [.openAccessibilitySettings])
    }

    @Test
    func unauthorizedGuideShowsAccessibilityAsCurrentStepBeforeSettingsAreOpened() {
        let viewState = PasteraSetupGuideViewState(
            isAccessibilityTrusted: false,
            didOpenAccessibilitySettings: false
        )

        #expect(viewState.progressTitle == "第 2 步 / 共 2 步")
        #expect(viewState.stepStates == [
            PasteraSetupGuideStepState(step: .installLocation, status: .completed),
            PasteraSetupGuideStepState(step: .accessibility, status: .current)
        ])
        #expect(viewState.primaryAction == .openAccessibilitySettings)
        #expect(viewState.secondaryAction == .dismiss)
    }

    @Test
    func unauthorizedGuideOnlyShowsRecheckActionAfterSettingsAreOpened() {
        let viewState = PasteraSetupGuideViewState(
            isAccessibilityTrusted: false,
            didOpenAccessibilitySettings: true
        )

        #expect(viewState.availableActions == [.recheckAccessibility])
    }

    @Test
    func guideShowsRecheckAsPrimaryAfterSettingsAreOpened() {
        let viewState = PasteraSetupGuideViewState(
            isAccessibilityTrusted: false,
            didOpenAccessibilitySettings: true
        )

        #expect(viewState.progressTitle == "第 2 步 / 共 2 步")
        #expect(viewState.primaryAction == .recheckAccessibility)
        #expect(viewState.secondaryAction == .openAccessibilitySettings)
    }

    @Test
    func authorizedGuideOnlyShowsFinishAction() {
        let viewState = PasteraSetupGuideViewState(
            isAccessibilityTrusted: true,
            didOpenAccessibilitySettings: true
        )

        #expect(viewState.availableActions == [.finish])
    }

    @Test
    func authorizedGuideMarksAllStepsCompleted() {
        let viewState = PasteraSetupGuideViewState(
            isAccessibilityTrusted: true,
            didOpenAccessibilitySettings: true
        )

        #expect(viewState.progressTitle == "已完成 2 / 2 步")
        #expect(viewState.stepStates == [
            PasteraSetupGuideStepState(step: .installLocation, status: .completed),
            PasteraSetupGuideStepState(step: .accessibility, status: .completed)
        ])
        #expect(viewState.primaryAction == .finish)
        #expect(viewState.secondaryAction == nil)
    }

    @Test
    func guideLayoutUsesSingleAlignedContentGrid() {
        #expect(PasteraSetupGuideLayout.windowSize.width == 680)
        #expect(PasteraSetupGuideLayout.windowSize.height == 430)
        #expect(PasteraSetupGuideLayout.contentWidth == 616)
        #expect(PasteraSetupGuideLayout.stepRowHeight == 74)
        #expect(PasteraSetupGuideLayout.noticeHeight == 64)
        #expect(
            PasteraSetupGuideLayout.stepMarkerWidth
                + PasteraSetupGuideLayout.stepTextLeading
                + PasteraSetupGuideLayout.stepStatusWidth
                < PasteraSetupGuideLayout.contentWidth
        )
    }
}
