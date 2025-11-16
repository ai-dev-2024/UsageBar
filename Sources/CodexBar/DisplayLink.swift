import Combine
import QuartzCore

/// Lightweight display link publisher to drive simple animations for the menu bar icon (macOS via CVDisplayLink).
final class DisplayLink {
    private let subject = PassthroughSubject<Void, Never>()
    private var link: CVDisplayLink?

    var publisher: AnyPublisher<Void, Never> {
        self.subject.eraseToAnyPublisher()
    }

    init() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let link = dl else { return }
        CVDisplayLinkSetOutputHandler(link) { [weak subject] _, _, _, _, _ in
            subject?.send(())
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(link)
        self.link = link
    }

    deinit {
        if let link { CVDisplayLinkStop(link) }
    }
}
