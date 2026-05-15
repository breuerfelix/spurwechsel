import CoreGraphics
import Foundation

struct ShellLayoutPolicy {
    private static let minimumContentWidth: CGFloat = 720
    private static let defaultLeftSidebarWidth: CGFloat = 288
    private static let defaultRightSidebarWidth: CGFloat = 272
    private static let minimumLeftSidebarWidth: CGFloat = 150
    private static let minimumRightSidebarWidth: CGFloat = 180
    private static let leftBranchNamesVisibleWidth: CGFloat = 240
    private static let rightBranchNamesVisibleWidth: CGFloat = 220
    private static let minimumMainWidthForCompression: CGFloat = 360
    private static let absoluteMinimumMainWidth: CGFloat = 320
    private static let minimumPreviewWidth: CGFloat = 260
    private static let defaultPreviewMinWidth: CGFloat = 300
    private static let defaultPreviewMaxWidth: CGFloat = 460

    let outerPadding: CGFloat
    let gap: CGFloat
    let showsLeftSidebar: Bool
    let showsPreview: Bool
    let showsRightSidebar: Bool
    let leftSidebarWidth: CGFloat
    let showsLeftSidebarBranchNames: Bool
    let leftSidebarWidthBounds: ClosedRange<CGFloat>
    let previewWidth: CGFloat
    let previewWidthBounds: ClosedRange<CGFloat>
    let rightSidebarWidth: CGFloat
    let showsRightSidebarBranchNames: Bool
    let rightSidebarWidthBounds: ClosedRange<CGFloat>
    let mainWidth: CGFloat

    init(size: CGSize, layout: AppLayoutState) {
        let compact = size.width < 1380
        outerPadding = compact ? SpurSpacing.sm : SpurSpacing.md
        gap = compact ? SpurSpacing.sm : SpurSpacing.md

        let preferredShowsLeftSidebar = layout.effectiveShowsLeftSidebar
        let preferredShowsPreview = layout.previewEnabled
        let preferredShowsRightSidebar = layout.showsRightSidebar

        var resolvedShowsLeftSidebar = preferredShowsLeftSidebar
        var resolvedShowsPreview = preferredShowsPreview
        var resolvedShowsRightSidebar = preferredShowsRightSidebar

        var resolvedLeftBounds = Self.minimumLeftSidebarWidth...Self.minimumLeftSidebarWidth
        var resolvedLeftWidth: CGFloat = 0
        var resolvedPreviewBounds = Self.minimumPreviewWidth...Self.minimumPreviewWidth
        var resolvedPreviewWidth: CGFloat = 0
        var resolvedRightBounds = Self.minimumRightSidebarWidth...Self.minimumRightSidebarWidth
        var resolvedRightWidth: CGFloat = 0
        var resolvedMainWidth: CGFloat = Self.minimumContentWidth

        while true {
            let panelCount = [
                resolvedShowsLeftSidebar,
                resolvedShowsPreview,
                resolvedShowsRightSidebar
            ].filter { $0 }.count
            let contentWidth = Self.contentWidth(
                size: size,
                outerPadding: outerPadding,
                gap: gap,
                panelCount: panelCount
            )
            let minimumRightWidth = resolvedShowsRightSidebar ? Self.minimumRightSidebarWidth : 0
            let minimumPreviewWidth = resolvedShowsPreview ? Self.minimumPreviewWidth : 0

            if resolvedShowsLeftSidebar {
                let maxLeftWidth = contentWidth - minimumRightWidth - minimumPreviewWidth - Self.minimumMainWidthForCompression
                if maxLeftWidth >= Self.minimumLeftSidebarWidth {
                    resolvedLeftBounds = Self.minimumLeftSidebarWidth...maxLeftWidth
                    let requestedLeftSidebarWidth = layout.preferredLeftSidebarWidth ?? Self.defaultLeftSidebarWidth
                    resolvedLeftWidth = Self.clamp(
                        requestedLeftSidebarWidth,
                        min: resolvedLeftBounds.lowerBound,
                        max: resolvedLeftBounds.upperBound
                    )
                } else {
                    if resolvedShowsRightSidebar {
                        resolvedShowsRightSidebar = false
                    } else if resolvedShowsPreview {
                        resolvedShowsPreview = false
                    } else {
                        resolvedShowsLeftSidebar = false
                    }
                    continue
                }
            } else {
                resolvedLeftBounds = Self.minimumLeftSidebarWidth...Self.minimumLeftSidebarWidth
                resolvedLeftWidth = 0
            }

            if resolvedShowsRightSidebar {
                let maxRightWidth = contentWidth - resolvedLeftWidth - minimumPreviewWidth - Self.minimumMainWidthForCompression
                if maxRightWidth >= Self.minimumRightSidebarWidth {
                    resolvedRightBounds = Self.minimumRightSidebarWidth...maxRightWidth
                    let requestedRightSidebarWidth = layout.preferredRightSidebarWidth ?? Self.defaultRightSidebarWidth
                    resolvedRightWidth = Self.clamp(
                        requestedRightSidebarWidth,
                        min: resolvedRightBounds.lowerBound,
                        max: resolvedRightBounds.upperBound
                    )
                } else {
                    resolvedShowsRightSidebar = false
                    continue
                }
            } else {
                resolvedRightBounds = Self.minimumRightSidebarWidth...Self.minimumRightSidebarWidth
                resolvedRightWidth = 0
            }

            if resolvedShowsPreview {
                let maxPreviewWidth = contentWidth - resolvedLeftWidth - resolvedRightWidth - Self.minimumMainWidthForCompression
                if maxPreviewWidth >= Self.minimumPreviewWidth {
                    let defaultPreviewWidth = Self.clamp(
                        contentWidth * 0.30,
                        min: Self.defaultPreviewMinWidth,
                        max: Self.defaultPreviewMaxWidth
                    )
                    let requestedPreviewWidth = layout.preferredPreviewWidth ?? defaultPreviewWidth
                    resolvedPreviewBounds = Self.minimumPreviewWidth...maxPreviewWidth
                    resolvedPreviewWidth = Self.clamp(
                        requestedPreviewWidth,
                        min: resolvedPreviewBounds.lowerBound,
                        max: resolvedPreviewBounds.upperBound
                    )
                } else {
                    if resolvedShowsRightSidebar {
                        resolvedShowsRightSidebar = false
                    } else {
                        resolvedShowsPreview = false
                    }
                    continue
                }
            } else {
                resolvedPreviewBounds = Self.minimumPreviewWidth...Self.minimumPreviewWidth
                resolvedPreviewWidth = 0
            }

            resolvedMainWidth = contentWidth - resolvedLeftWidth - resolvedRightWidth - resolvedPreviewWidth
            if resolvedMainWidth >= Self.minimumMainWidthForCompression {
                break
            }
            if resolvedShowsRightSidebar {
                resolvedShowsRightSidebar = false
                continue
            }
            if resolvedShowsPreview {
                resolvedShowsPreview = false
                continue
            }
            if resolvedShowsLeftSidebar {
                resolvedShowsLeftSidebar = false
                continue
            }
            break
        }

        showsLeftSidebar = resolvedShowsLeftSidebar
        showsPreview = resolvedShowsPreview
        showsRightSidebar = resolvedShowsRightSidebar
        leftSidebarWidth = resolvedLeftWidth
        showsLeftSidebarBranchNames = resolvedShowsLeftSidebar && resolvedLeftWidth >= Self.leftBranchNamesVisibleWidth
        leftSidebarWidthBounds = resolvedLeftBounds
        previewWidth = resolvedPreviewWidth
        previewWidthBounds = resolvedPreviewBounds
        rightSidebarWidth = resolvedRightWidth
        showsRightSidebarBranchNames = resolvedShowsRightSidebar && resolvedRightWidth >= Self.rightBranchNamesVisibleWidth
        rightSidebarWidthBounds = resolvedRightBounds
        mainWidth = max(resolvedMainWidth, Self.absoluteMinimumMainWidth)
    }

    private static func contentWidth(
        size: CGSize,
        outerPadding: CGFloat,
        gap: CGFloat,
        panelCount: Int
    ) -> CGFloat {
        max(size.width - (outerPadding * 2) - (CGFloat(panelCount + 1) * gap), minimumContentWidth)
    }

    private static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}
