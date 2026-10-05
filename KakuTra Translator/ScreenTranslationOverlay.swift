import AppKit
import SwiftUI

struct ScreenTranslationOverlayItem: Identifiable {
    let id: String
    let rect: CGRect
    let originalText: String
    let translation: String
    let style: ScreenTranslationPatchStyle
    let fontSize: CGFloat
}

struct ScreenTranslationObservation {
    let id: String
    let cacheKey: ScreenTranslationCacheKey
    let originalText: String
    var rect: CGRect
    let style: ScreenTranslationPatchStyle
    var fontSize: CGFloat

    func overlayItem(translation: String) -> ScreenTranslationOverlayItem {
        ScreenTranslationOverlayItem(
            id: id,
            rect: rect,
            originalText: originalText,
            translation: translation,
            style: style,
            fontSize: fontSize
        )
    }
}

private struct ScreenTranslationOverlayView: View {
    let screenFrame: CGRect
    let items: [ScreenTranslationOverlayItem]
    let protectedTextRects: [CGRect]

    private var localProtectedTextRects: [CGRect] {
        protectedTextRects.map { rect in
            CGRect(
                x: rect.minX - screenFrame.minX,
                y: screenFrame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
    }

    var body: some View {
        let localProtectedRects = localProtectedTextRects
        return ZStack(alignment: .topLeading) {
            ForEach(items) { item in
                let sourceRect = CGRect(
                    x: item.rect.minX - screenFrame.minX,
                    y: screenFrame.maxY - item.rect.maxY,
                    width: item.rect.width,
                    height: item.rect.height
                )
                let maximumPatchWidth = ScreenTranslationPatchClearance.maximumRightwardWidth(
                    for: sourceRect,
                    protectedRects: localProtectedRects,
                    screenSize: screenFrame.size
                )
                let maximumPatchHeight = ScreenTranslationPatchClearance.maximumDownwardHeight(
                    for: sourceRect,
                    maximumWidth: maximumPatchWidth,
                    protectedRects: localProtectedRects,
                    screenSize: screenFrame.size
                )
                let content = ScreenTranslationPatchContent(
                    originalText: item.originalText,
                    translationState: .ready(item.translation),
                    sourceRect: CGRect(origin: .zero, size: sourceRect.size),
                    bodyFontSize: item.fontSize,
                    style: item.style,
                    maximumPatchWidth: maximumPatchWidth,
                    maximumPatchHeight: maximumPatchHeight
                )
                let layout = ScreenTranslationPatchLayout.resolve(
                    sourceRect: content.sourceRect,
                    preferredFontSize: item.fontSize,
                    translatedText: item.translation,
                    maximumPatchWidth: maximumPatchWidth,
                    maximumPatchHeight: maximumPatchHeight
                )
                let patchOrigin = CGPoint(
                    x: min(max(0, sourceRect.minX), screenFrame.width - layout.patchSize.width),
                    y: min(max(0, sourceRect.minY), screenFrame.height - layout.patchSize.height)
                )

                ScreenTranslationPatchView(content: content)
                    .frame(width: layout.patchSize.width, height: layout.patchSize.height)
                    .position(
                        x: patchOrigin.x + layout.patchSize.width / 2,
                        y: patchOrigin.y + layout.patchSize.height / 2
                    )
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height)
        .background(.clear)
        .ignoresSafeArea()
    }

}

@MainActor
final class ScreenTranslationOverlayWindowController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ScreenTranslationOverlayView>?

    func show(
        items: [ScreenTranslationOverlayItem],
        protectedTextRects: [CGRect],
        on screen: NSScreen
    ) {
        guard !items.isEmpty else {
            hide()
            return
        }

        let panel: NSPanel
        if let existing = self.panel {
            panel = existing
        } else {
            panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            let hostingView = NSHostingView(rootView: ScreenTranslationOverlayView(
                screenFrame: screen.frame,
                items: items,
                protectedTextRects: protectedTextRects
            ))
            panel.contentView = hostingView
            self.panel = panel
            self.hostingView = hostingView
            CaptureExclusionRegistry.shared.register(panel)
        }

        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: true)
        }
        hostingView?.rootView = ScreenTranslationOverlayView(
            screenFrame: screen.frame,
            items: items,
            protectedTextRects: protectedTextRects
        )
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
