import SwiftUI

private enum ShellResizeDirection {
    case growWithDrag
    case shrinkWithDrag
}

private struct ShellHorizontalResizeHandle: View {
    let currentWidth: CGFloat
    let allowedRange: ClosedRange<CGFloat>
    let handleWidth: CGFloat
    let accessibilityID: String
    let direction: ShellResizeDirection
    @Binding var dragStartWidth: CGFloat?
    let onWidthChanged: (CGFloat, ClosedRange<CGFloat>) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        Color.clear
            .frame(width: handleWidth)
            .frame(maxHeight: .infinity)
            .padding(.vertical, SpurSpacing.sm)
            .background(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .modifier(HorizontalResizeCursorModifier())
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = currentWidth
                        }
                        let startWidth = dragStartWidth ?? currentWidth
                        let dragDelta = value.location.x - value.startLocation.x
                        let proposedWidth: CGFloat
                        switch direction {
                        case .growWithDrag:
                            proposedWidth = startWidth + dragDelta
                        case .shrinkWithDrag:
                            proposedWidth = startWidth - dragDelta
                        }
                        onWidthChanged(proposedWidth, allowedRange)
                    }
                    .onEnded { _ in
                        dragStartWidth = nil
                        onDragEnded()
                    }
            )
            .accessibilityIdentifier(accessibilityID)
    }
}

struct LeftSidebarResizeHandle: View {
    let width: CGFloat
    let allowedRange: ClosedRange<CGFloat>
    let handleWidth: CGFloat
    @Binding var dragStartWidth: CGFloat?
    let onWidthChanged: (CGFloat, ClosedRange<CGFloat>) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        ShellHorizontalResizeHandle(
            currentWidth: width,
            allowedRange: allowedRange,
            handleWidth: handleWidth,
            accessibilityID: "sidebar.left.resize-handle",
            direction: .growWithDrag,
            dragStartWidth: $dragStartWidth,
            onWidthChanged: onWidthChanged,
            onDragEnded: onDragEnded
        )
    }
}

struct PreviewResizeHandle: View {
    let width: CGFloat
    let allowedRange: ClosedRange<CGFloat>
    let handleWidth: CGFloat
    @Binding var dragStartWidth: CGFloat?
    let onWidthChanged: (CGFloat, ClosedRange<CGFloat>) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        ShellHorizontalResizeHandle(
            currentWidth: width,
            allowedRange: allowedRange,
            handleWidth: handleWidth,
            accessibilityID: "preview.resize-handle",
            direction: .shrinkWithDrag,
            dragStartWidth: $dragStartWidth,
            onWidthChanged: onWidthChanged,
            onDragEnded: onDragEnded
        )
    }
}

struct RightSidebarResizeHandle: View {
    let width: CGFloat
    let allowedRange: ClosedRange<CGFloat>
    let handleWidth: CGFloat
    @Binding var dragStartWidth: CGFloat?
    let onWidthChanged: (CGFloat, ClosedRange<CGFloat>) -> Void
    let onDragEnded: () -> Void

    var body: some View {
        ShellHorizontalResizeHandle(
            currentWidth: width,
            allowedRange: allowedRange,
            handleWidth: handleWidth,
            accessibilityID: "sidebar.right.resize-handle",
            direction: .shrinkWithDrag,
            dragStartWidth: $dragStartWidth,
            onWidthChanged: onWidthChanged,
            onDragEnded: onDragEnded
        )
    }
}
