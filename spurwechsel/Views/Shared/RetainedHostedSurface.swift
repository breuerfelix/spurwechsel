import AppKit

protocol SurfaceSlotTracking: AnyObject {
    var surfaceSlot: SurfaceSlot? { get set }
}

@MainActor
final class RetainedHostedSurface<HostedView: NSView> {
    let view: HostedView

    private weak var ownerContainer: RetainedHostedSurfaceContainer<HostedView>?

    init(view: HostedView) {
        self.view = view
    }

    func attach(to container: RetainedHostedSurfaceContainer<HostedView>) {
        if ownerContainer === container,
           view.superview === container {
            return
        }

        ownerContainer = container
        container.setHostedView(view)
    }

    func release(from container: RetainedHostedSurfaceContainer<HostedView>) {
        guard ownerContainer === container else {
            return
        }

        container.clearHostedViewIfAttached(view)
        ownerContainer = nil
    }

    func performIfCurrentOwner(
        in container: RetainedHostedSurfaceContainer<HostedView>,
        _ update: (HostedView) -> Void
    ) {
        guard ownerContainer === container,
              view.superview === container
        else {
            return
        }

        update(view)
    }

    func performAsyncIfCurrentOwner(
        in container: RetainedHostedSurfaceContainer<HostedView>,
        _ update: @escaping (HostedView) -> Void
    ) {
        DispatchQueue.main.async { [weak self, weak container] in
            guard let self, let container else {
                return
            }
            self.performIfCurrentOwner(in: container, update)
        }
    }
}

final class RetainedHostedSurfaceContainer<HostedView: NSView>: NSView, SurfaceSlotTracking {
    private(set) weak var hostedView: HostedView?
    var surfaceSlot: SurfaceSlot?
    var onSurfaceFocused: ((SurfaceSlot) -> Void)?

    private var focusRequest: SurfaceFocusRequest?
    private var focusHandler: ((HostedView) -> Bool)?
    private var fulfilledFocusRequestID: Int?
    private var inFlightFocusRequestID: Int?

    func setHostedView(_ view: HostedView) {
        if let hostedView,
           hostedView !== view,
           hostedView.superview === self {
            hostedView.removeFromSuperview()
        }

        hostedView = view

        guard view.superview !== self else {
            return
        }

        if view.superview != nil {
            view.removeFromSuperview()
        }

        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        applyPendingFocusIfNeeded()
    }

    func clearHostedViewIfAttached(_ view: HostedView) {
        guard hostedView === view else {
            return
        }

        if view.superview === self {
            view.removeFromSuperview()
        }
        hostedView = nil
    }

    func configureFocus(
        slot: SurfaceSlot,
        request: SurfaceFocusRequest?,
        onSurfaceFocused: @escaping (SurfaceSlot) -> Void,
        focusHandler: @escaping (HostedView) -> Bool
    ) {
        self.surfaceSlot = slot
        self.focusRequest = request
        self.onSurfaceFocused = onSurfaceFocused
        self.focusHandler = focusHandler
        applyPendingFocusIfNeeded()
    }

    private func applyPendingFocusIfNeeded() {
        guard hostedView != nil,
              let slot = surfaceSlot,
              let request = focusRequest,
              request.slot == slot
        else {
            return
        }
        guard fulfilledFocusRequestID != request.id,
              inFlightFocusRequestID != request.id
        else {
            return
        }

        inFlightFocusRequestID = request.id
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.inFlightFocusRequestID = nil
            guard let hostedView = self.hostedView,
                  let activeSlot = self.surfaceSlot,
                  activeSlot == slot,
                  self.focusRequest?.id == request.id
            else {
                return
            }

            let didFocus = self.focusHandler?(hostedView) ?? false
            guard didFocus else {
                return
            }

            self.fulfilledFocusRequestID = request.id
            self.onSurfaceFocused?(activeSlot)
        }
    }
}
