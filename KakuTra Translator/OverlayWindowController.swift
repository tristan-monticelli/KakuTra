import AppKit
import Combine
import SwiftUI

private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
enum WordOverlayPlacement {
    case below
    case above
}

enum WordOverlayLayout {
    static let gap: CGFloat = 12
    static let edgeInset: CGFloat = 50

    static func resolve(
        panelHeight: CGFloat,
        anchor: CGPoint,
        screenFrame: CGRect
    ) -> WordOverlayPlacement {
        let spaceBelow = anchor.y - screenFrame.minY - gap - edgeInset
        let spaceAbove = screenFrame.maxY - anchor.y - gap - edgeInset

        if panelHeight <= spaceBelow {
            return .below
        }

        if panelHeight <= spaceAbove {
            return .above
        }

        return spaceBelow >= spaceAbove ? .below : .above
    }
}

enum ParagraphOverlayPlacement {
    case below
    case above
}

struct ParagraphOverlayLayoutResult {
    let placement: ParagraphOverlayPlacement
    let maxPanelHeight: CGFloat
}

enum ParagraphOverlayLayout {
    static let gap: CGFloat = 8
    static let edgeInset: CGFloat = 8

    static func resolve(
        naturalPanelHeight: CGFloat,
        spaceBelow: CGFloat,
        spaceAbove: CGFloat
    ) -> ParagraphOverlayLayoutResult {
        let availableBelow = max(1, spaceBelow - gap - edgeInset)
        let availableAbove = max(1, spaceAbove - gap - edgeInset)

        if naturalPanelHeight <= availableBelow {
            return ParagraphOverlayLayoutResult(
                placement: .below,
                maxPanelHeight: availableBelow
            )
        }

        if naturalPanelHeight <= availableAbove {
            return ParagraphOverlayLayoutResult(
                placement: .above,
                maxPanelHeight: availableAbove
            )
        }

        if availableBelow >= availableAbove {
            return ParagraphOverlayLayoutResult(
                placement: .below,
                maxPanelHeight: availableBelow
            )
        }

        return ParagraphOverlayLayoutResult(
            placement: .above,
            maxPanelHeight: availableAbove
        )
    }
}

// MARK: - Overlay Window Controller

final class OverlayWindowController: NSWindowController {
    private static let allSpacesCollectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .stationary,
    ]

    private let model: AppModel
    private let hostingView: NSHostingView<AnyView>
    private var measurementHostingView: NSHostingView<AnyView>?
    private var lastAnchor: CGPoint?
    private var manualOrigin: CGPoint?
    private var dragStartOrigin: CGPoint?
    private var currentParagraphOverlayMaxHeight: CGFloat?
    private var currentParagraphOverlayScrollingEnabled = false
    private var paragraphFrameAnimationTask: Task<Void, Never>?
    private var paragraphFrameAnimationID = UUID()
    private let frameTolerance: CGFloat = 0.5
    private let paragraphOverlayRenderedHeightSafetyInset: CGFloat = 8
    private let paragraphFrameAnimationDuration: TimeInterval = 0.18
    private let paragraphFrameAnimationStepNanoseconds: UInt64 = 16_666_667

    var isManualParagraphPositioningActive: Bool {
        dragStartOrigin != nil
    }

    var hasManualParagraphPosition: Bool {
        manualOrigin != nil
    }

    init(model: AppModel) {
        self.model = model
        let initialRootView = AnyView(OverlayView().environmentObject(model))
        hostingView = NSHostingView(rootView: initialRootView)
        let panel = OverlayPanel(
            contentRect: CGRect(x: 0, y: 0, width: 380, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.allowsToolTipsWhenApplicationIsInactive = true
        panel.level = .statusBar
        panel.collectionBehavior = Self.allSpacesCollectionBehavior
        panel.ignoresMouseEvents = true
        panel.acceptsMouseMovedEvents = true
        panel.isMovableByWindowBackground = false
        super.init(window: panel)
        CaptureExclusionRegistry.shared.register(panel)
    }

    /// 设置窗口是否接受鼠标事件
    func setInteractive(_ interactive: Bool) {
        guard let window, window.ignoresMouseEvents != !interactive else { return }
        window.ignoresMouseEvents = !interactive
    }

    func isMouseInside(point: CGPoint) -> Bool {
        guard let window, window.isVisible else { return false }
        return window.frame.contains(point)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }

    var visibleFrame: CGRect? {
        guard let window, window.isVisible else { return nil }
        return window.frame
    }

    /// Reassert the panel's Space membership after Mission Control switches
    /// Spaces. macOS can keep an ordered window marked as visible while it is
    /// no longer frontmost in the newly active Space.
    func reassertForActiveSpace() {
        guard let window else { return }
        window.collectionBehavior = Self.allSpacesCollectionBehavior
        guard window.isVisible else { return }
        window.orderFrontRegardless()
    }

    func show(
        at anchor: CGPoint,
        makeKey: Bool = false,
        onOrderedFront: (() -> Void)? = nil
    ) {
        guard let window else { return }
        lastAnchor = anchor
        let wasVisible = window.isVisible

        if !wasVisible {
            hostingView.rootView = overlayRootView(
                paragraphOverlayMaxHeight: currentParagraphOverlayMaxHeight,
                paragraphOverlayScrollingEnabled: currentParagraphOverlayScrollingEnabled
            )
        }

        let targetFrame = measuredFrame(for: anchor)
        window.collectionBehavior = Self.allSpacesCollectionBehavior

        if !wasVisible {
            cancelParagraphFrameAnimation()
            window.setFrame(targetFrame, display: true)
        } else {
            applyFrameIfNeeded(targetFrame)
        }

        // Reorder even when AppKit reports the window as visible. During a
        // Space switch that state can refer to the previous Space, which used
        // to make the overlay silently remain there.
        window.orderFrontRegardless()
        onOrderedFront?()
        if makeKey {
            window.makeKey()
        }
    }

    func move(to anchor: CGPoint) {
        guard let window else { return }
        lastAnchor = anchor
        manualOrigin = nil
        dragStartOrigin = nil
        cancelParagraphFrameAnimation()
        guard window.isVisible else { return }

        let screenFrame = visibleScreenFrame(for: anchor)
        let origin = anchoredOrigin(for: anchor, size: window.frame.size, in: screenFrame)
        let targetFrame = CGRect(origin: origin, size: window.frame.size)
        applyFrameIfNeeded(targetFrame)
    }

    /// 将面板对齐到句子矩形（正上方或正下方，取决于哪侧空间更大）
    func alignToSentenceRect(_ sentenceRect: CGRect, animated: Bool = true) {
        guard window != nil else { return }

        // 取句子中心点所在屏幕
        let midPoint = CGPoint(x: sentenceRect.midX, y: sentenceRect.midY)
        let screen = NSScreen.screens.first(where: {
            NSMouseInRect(midPoint, $0.frame, false)
        }) ?? NSScreen.main
        let screenFrame = screen?.visibleFrame ?? .zero

        // AppKit Y 轴向上：minY 是物理下边，maxY 是物理上边
        let gap = ParagraphOverlayLayout.gap
        let spaceBelow = sentenceRect.minY - screenFrame.minY
        let spaceAbove = screenFrame.maxY - sentenceRect.maxY
        let naturalSize = measureParagraphOverlaySize(
            maxHeight: nil,
            scrollingEnabled: false
        )
        let correctedNaturalHeight = naturalSize.height + paragraphOverlayRenderedHeightSafetyInset
        let layout = ParagraphOverlayLayout.resolve(
            naturalPanelHeight: correctedNaturalHeight,
            spaceBelow: spaceBelow,
            spaceAbove: spaceAbove
        )
        let requiresScrolling = correctedNaturalHeight > layout.maxPanelHeight + frameTolerance
        let finalMaxHeight = requiresScrolling ? layout.maxPanelHeight : nil
        let measuredContentSize = measureParagraphOverlaySize(
            maxHeight: finalMaxHeight,
            scrollingEnabled: requiresScrolling
        )
        applyParagraphOverlayLayout(
            maxHeight: finalMaxHeight,
            scrollingEnabled: requiresScrolling
        )

        if hasManualParagraphPosition {
            let targetFrame = measuredFrame(for: CGPoint(x: sentenceRect.midX, y: sentenceRect.midY))
            applyFrameIfNeeded(targetFrame)
            return
        }

        let displayedContentSize = currentRenderedParagraphOverlaySize()
        let contentSize = CGSize(
            width: max(measuredContentSize.width, displayedContentSize.width),
            height: max(measuredContentSize.height, displayedContentSize.height)
                + paragraphOverlayRenderedHeightSafetyInset
        )

        let panelWidth = contentSize.width
        let panelHeight = contentSize.height

        let desiredY: CGFloat
        switch layout.placement {
        case .below:
            // 句子正下方（面板顶边贴近句子底边）
            desiredY = sentenceRect.minY - panelHeight - gap
        case .above:
            // 句子正上方（面板底边贴近句子顶边）
            desiredY = sentenceRect.maxY + gap
        }

        // 水平左对齐句子，clamp 到屏幕范围内
        let margin: CGFloat = 8
        var panelX = sentenceRect.minX
        panelX = max(screenFrame.minX + margin, panelX)
        panelX = min(screenFrame.maxX - panelWidth - margin, panelX)

        let minPanelY = screenFrame.minY + ParagraphOverlayLayout.edgeInset
        let maxPanelY = screenFrame.maxY - panelHeight - ParagraphOverlayLayout.edgeInset
        let panelY = min(max(desiredY, minPanelY), maxPanelY)
        let targetFrame = CGRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight)

        if animated {
            applyFrameAnimated(targetFrame)
        } else {
            applyFrameIfNeeded(targetFrame)
        }
    }

    func beginManualPositioning() {
        guard let window, window.isVisible else { return }
        cancelParagraphFrameAnimation()
        dragStartOrigin = window.frame.origin
        manualOrigin = window.frame.origin
    }

    func moveBy(translation: CGSize) {
        guard let window, window.isVisible else { return }
        cancelParagraphFrameAnimation()

        let baseOrigin = dragStartOrigin ?? manualOrigin ?? window.frame.origin
        let proposedOrigin = CGPoint(
            x: baseOrigin.x + translation.width,
            y: baseOrigin.y - translation.height
        )
        let screenPoint = CGPoint(
            x: proposedOrigin.x + window.frame.width / 2,
            y: proposedOrigin.y + window.frame.height / 2
        )
        let screenFrame = visibleScreenFrame(for: screenPoint)
        let clamped = clampedOrigin(proposedOrigin, size: window.frame.size, in: screenFrame)

        manualOrigin = clamped
        applyOriginIfNeeded(clamped)
    }

    func endManualPositioning() {
        if let window, window.isVisible {
            manualOrigin = window.frame.origin
        }
        dragStartOrigin = nil
    }

    func refreshLayoutIfNeeded(at anchor: CGPoint? = nil) {
        guard let window else { return }
        guard window.isVisible else {
            if let anchor {
                lastAnchor = anchor
            }
            return
        }

        let effectiveAnchor = anchor ?? lastAnchor ?? CGPoint(x: window.frame.midX, y: window.frame.maxY)
        lastAnchor = effectiveAnchor
        let targetFrame = measuredFrame(for: effectiveAnchor)
        applyFrameIfNeeded(targetFrame)
    }

    func hide() {
        lastAnchor = nil
        manualOrigin = nil
        dragStartOrigin = nil
        cancelParagraphFrameAnimation()
        currentParagraphOverlayMaxHeight = nil
        currentParagraphOverlayScrollingEnabled = false
        hostingView.rootView = AnyView(EmptyView().environmentObject(model))
        measurementHostingView = nil
        window?.orderOut(nil)
    }

    private func measuredFrame(for anchor: CGPoint) -> CGRect {
        applyParagraphOverlayLayout(
            maxHeight: currentParagraphOverlayMaxHeight,
            scrollingEnabled: currentParagraphOverlayScrollingEnabled
        )
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let origin: CGPoint

        if let manualOrigin {
            let screenPoint = CGPoint(
                x: manualOrigin.x + size.width / 2,
                y: manualOrigin.y + size.height / 2
            )
            let screenFrame = visibleScreenFrame(for: screenPoint)
            origin = clampedOrigin(manualOrigin, size: size, in: screenFrame)
            self.manualOrigin = origin
        } else {
            let screenFrame = visibleScreenFrame(for: anchor)
            origin = anchoredOrigin(for: anchor, size: size, in: screenFrame)
        }

        return CGRect(origin: origin, size: size)
    }

    private func measureParagraphOverlaySize(
        maxHeight: CGFloat?,
        scrollingEnabled: Bool
    ) -> CGSize {
        let rootView = overlayRootView(
            paragraphOverlayMaxHeight: maxHeight,
            paragraphOverlayScrollingEnabled: scrollingEnabled
        )
        if measurementHostingView == nil {
            measurementHostingView = NSHostingView(rootView: rootView)
        } else {
            measurementHostingView?.rootView = rootView
        }
        measurementHostingView?.invalidateIntrinsicContentSize()
        measurementHostingView?.layoutSubtreeIfNeeded()
        return measurementHostingView?.fittingSize ?? .zero
    }

    private func applyParagraphOverlayLayout(
        maxHeight: CGFloat?,
        scrollingEnabled: Bool
    ) {
        let requiresRootViewUpdate = currentParagraphOverlayMaxHeight != maxHeight
            || currentParagraphOverlayScrollingEnabled != scrollingEnabled

        if requiresRootViewUpdate {
            currentParagraphOverlayMaxHeight = maxHeight
            currentParagraphOverlayScrollingEnabled = scrollingEnabled
            hostingView.rootView = overlayRootView(
                paragraphOverlayMaxHeight: maxHeight,
                paragraphOverlayScrollingEnabled: scrollingEnabled
            )
        }

        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
    }

    private func currentRenderedParagraphOverlaySize() -> CGSize {
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize
    }

    private func overlayRootView(
        paragraphOverlayMaxHeight: CGFloat?,
        paragraphOverlayScrollingEnabled: Bool = false
    ) -> AnyView {
        AnyView(
            OverlayView(
                paragraphOverlayMaxHeightOverride: paragraphOverlayMaxHeight,
                paragraphOverlayScrollingEnabledOverride: paragraphOverlayScrollingEnabled
            )
                .environmentObject(model)
        )
    }

    private func visibleScreenFrame(for anchor: CGPoint) -> CGRect {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(anchor, $0.frame, false) }) ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func applyFrameAnimated(_ targetFrame: CGRect) {
        guard let window else { return }
        guard frameNeedsUpdate(from: window.frame, to: targetFrame) else { return }
        cancelParagraphFrameAnimation()

        let startFrame = window.frame
        let animationID = UUID()
        paragraphFrameAnimationID = animationID

        paragraphFrameAnimationTask = Task { @MainActor [weak self] in
            guard let self, let window = self.window else { return }

            let startTime = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                let rawProgress = min(max(elapsed / self.paragraphFrameAnimationDuration, 0), 1)
                let easedProgress = self.easeInOutProgress(rawProgress)
                let interpolatedFrame = self.interpolatedFrame(
                    from: startFrame,
                    to: targetFrame,
                    progress: easedProgress
                )
                window.setFrame(interpolatedFrame, display: true)

                if rawProgress >= 1 {
                    break
                }

                try? await Task.sleep(nanoseconds: self.paragraphFrameAnimationStepNanoseconds)
            }

            guard !Task.isCancelled else {
                if self.paragraphFrameAnimationID == animationID {
                    self.paragraphFrameAnimationTask = nil
                }
                return
            }

            window.setFrame(targetFrame, display: true)
            self.hostingView.layoutSubtreeIfNeeded()
            if self.paragraphFrameAnimationID == animationID {
                self.paragraphFrameAnimationTask = nil
            }
        }
    }

    private func applyFrameIfNeeded(_ targetFrame: CGRect) {
        guard let window else { return }
        guard frameNeedsUpdate(from: window.frame, to: targetFrame) else { return }
        cancelParagraphFrameAnimation()

        let widthDelta = abs(window.frame.size.width - targetFrame.size.width)
        let heightDelta = abs(window.frame.size.height - targetFrame.size.height)
        if widthDelta <= frameTolerance, heightDelta <= frameTolerance {
            applyOriginIfNeeded(targetFrame.origin)
            return
        }

        window.setFrame(targetFrame, display: true)
        hostingView.layoutSubtreeIfNeeded()
    }

    private func applyOriginIfNeeded(_ targetOrigin: CGPoint) {
        guard let window else { return }

        let xNeedsUpdate = abs(window.frame.origin.x - targetOrigin.x) > frameTolerance
        let yNeedsUpdate = abs(window.frame.origin.y - targetOrigin.y) > frameTolerance
        guard xNeedsUpdate || yNeedsUpdate else { return }

        cancelParagraphFrameAnimation()
        window.setFrameOrigin(targetOrigin)
    }

    private func frameNeedsUpdate(from current: CGRect, to target: CGRect) -> Bool {
        abs(current.origin.x - target.origin.x) > frameTolerance
            || abs(current.origin.y - target.origin.y) > frameTolerance
            || abs(current.size.width - target.size.width) > frameTolerance
            || abs(current.size.height - target.size.height) > frameTolerance
    }

    private func anchoredOrigin(for anchor: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        let placement = WordOverlayLayout.resolve(
            panelHeight: size.height,
            anchor: anchor,
            screenFrame: screenFrame
        )

        let offsetX: CGFloat = 14
        let shadowMargin: CGFloat = 30

        // If placing the card to the right of the cursor exceeds screen bounds,
        // place it to the left of the cursor so the cursor is never trapped inside the card.
        let proposedX: CGFloat
        if anchor.x + offsetX + size.width > screenFrame.maxX - shadowMargin {
            proposedX = anchor.x - offsetX - size.width
        } else {
            proposedX = anchor.x + offsetX
        }

        let proposedOrigin: CGPoint
        switch placement {
        case .below:
            proposedOrigin = CGPoint(x: proposedX, y: anchor.y - WordOverlayLayout.gap - size.height)
        case .above:
            proposedOrigin = CGPoint(x: proposedX, y: anchor.y + WordOverlayLayout.gap)
        }

        var origin = clampedOrigin(proposedOrigin, size: size, in: screenFrame)

        // Safety guarantee: Ensure the cursor is NEVER inside the overlay frame when spawned!
        let frame = CGRect(origin: origin, size: size)
        if frame.contains(anchor) {
            if anchor.x - screenFrame.minX > screenFrame.maxX - anchor.x {
                origin.x = max(screenFrame.minX + shadowMargin, anchor.x - size.width - offsetX)
            } else {
                origin.x = min(screenFrame.maxX - size.width - shadowMargin, anchor.x + offsetX)
            }
        }

        return origin
    }

    private func clampedOrigin(_ proposedOrigin: CGPoint, size: CGSize, in screenFrame: CGRect) -> CGPoint {
        var origin = proposedOrigin
        let shadowMargin: CGFloat = 50
        let minX = screenFrame.minX + shadowMargin
        let maxX = screenFrame.maxX - size.width - shadowMargin
        let minY = screenFrame.minY + shadowMargin
        let maxY = screenFrame.maxY - size.height - shadowMargin
        origin.x = min(max(origin.x, minX), maxX)
        origin.y = min(max(origin.y, minY), maxY)
        return origin
    }

    private func cancelParagraphFrameAnimation() {
        paragraphFrameAnimationTask?.cancel()
        paragraphFrameAnimationTask = nil
        paragraphFrameAnimationID = UUID()
    }

    private func easeInOutProgress(_ progress: Double) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        let eased = clamped < 0.5
            ? 4 * clamped * clamped * clamped
            : 1 - pow(-2 * clamped + 2, 3) / 2
        return CGFloat(eased)
    }

    private func interpolatedFrame(from start: CGRect, to end: CGRect, progress: CGFloat) -> CGRect {
        CGRect(
            x: interpolatedScalar(from: start.origin.x, to: end.origin.x, progress: progress),
            y: interpolatedScalar(from: start.origin.y, to: end.origin.y, progress: progress),
            width: interpolatedScalar(from: start.size.width, to: end.size.width, progress: progress),
            height: interpolatedScalar(from: start.size.height, to: end.size.height, progress: progress)
        )
    }

    private func interpolatedScalar(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}
