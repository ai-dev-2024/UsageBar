import AppKit
import CodexBarCore
import OSLog
import WebKit

@MainActor
final class OpenAICreditsPurchaseWindowController: NSWindowController, WKNavigationDelegate {
    private static let defaultSize = NSSize(width: 980, height: 760)
    private static let autoStartScript = """
    (() => {
      if (window.__codexbarAutoBuyCreditsStarted) return 'already';
      const buttonSelector = 'button, a, [role="button"], input[type="button"], input[type="submit"]';
      const textOf = el => {
        const raw = el && (el.innerText || el.textContent) ? String(el.innerText || el.textContent) : '';
        return raw.trim();
      };
      const matches = text => {
        const lower = String(text || '').toLowerCase();
        if (!lower.includes('credit')) return false;
        return (
          lower.includes('buy') ||
          lower.includes('add') ||
          lower.includes('purchase') ||
          lower.includes('top up') ||
          lower.includes('top-up')
        );
      };
      const matchesAddMore = text => {
        const lower = String(text || '').toLowerCase();
        return lower.includes('add more');
      };
      const labelFor = el => {
        if (!el) return '';
        return textOf(el) || el.getAttribute('aria-label') || el.getAttribute('title') || el.value || '';
      };
      const clickButton = (el) => {
        if (!el) return false;
        try {
          el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
        } catch {
          try {
            el.click();
          } catch {
            return false;
          }
        }
        return true;
      };
      const pickLikelyButton = (buttons) => {
        if (!buttons || buttons.length === 0) return null;
        const labeled = buttons.find(btn => {
          const label = labelFor(btn);
          if (matches(label) || matchesAddMore(label)) return true;
          const aria = String(btn.getAttribute('aria-label') || '').toLowerCase();
          return aria.includes('credit') || aria.includes('buy') || aria.includes('add');
        });
        return labeled || buttons[0];
      };
      const findAddMoreButton = () => {
        const buttons = Array.from(document.querySelectorAll(buttonSelector));
        return buttons.find(btn => matchesAddMore(labelFor(btn))) || null;
      };
      const findNextButton = () => {
        const buttons = Array.from(document.querySelectorAll(buttonSelector));
        return buttons.find(btn => {
          if (btn.type && String(btn.type).toLowerCase() === 'submit') return true;
          const label = labelFor(btn).toLowerCase();
          return label === 'next' || label.startsWith('next ');
        }) || null;
      };
      const isDisabled = (el) => {
        if (!el) return true;
        if (el.disabled) return true;
        const ariaDisabled = String(el.getAttribute('aria-disabled') || '').toLowerCase();
        if (ariaDisabled === 'true') return true;
        if (el.classList && (el.classList.contains('disabled') || el.classList.contains('is-disabled'))) {
          return true;
        }
        return false;
      };
      const forceClickElement = (el) => {
        if (!el) return false;
        const rect = el.getBoundingClientRect ? el.getBoundingClientRect() : null;
        if (rect) {
          const x = rect.left + rect.width / 2;
          const y = rect.top + rect.height / 2;
          const target = document.elementFromPoint(x, y);
          if (target) {
            try {
              target.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true, view: window }));
              return true;
            } catch {
              return false;
            }
          }
        }
        return false;
      };
      const requestSubmit = (el) => {
        if (!el || !el.closest) return false;
        const form = el.closest('form');
        if (!form) return false;
        if (typeof form.requestSubmit === 'function') {
          form.requestSubmit(el);
          return true;
        }
        if (typeof form.submit === 'function') {
          form.submit();
          return true;
        }
        return false;
      };
      const clickNextIfReady = () => {
        const nextButton = findNextButton();
        if (!nextButton) return false;
        if (isDisabled(nextButton)) return false;
        const rect = nextButton.getBoundingClientRect ? nextButton.getBoundingClientRect() : null;
        if (rect && (rect.width < 2 || rect.height < 2)) return false;
        nextButton.focus?.();
        if (requestSubmit(nextButton)) return true;
        if (clickButton(nextButton)) return true;
        return forceClickElement(nextButton);
      };
      const startNextPolling = (initialDelay = 500, interval = 500, maxAttempts = 90) => {
        if (window.__codexbarNextPolling) return;
        window.__codexbarNextPolling = true;
        setTimeout(() => {
          let attempts = 0;
          const nextTimer = setInterval(() => {
            attempts += 1;
            if (clickNextIfReady() || attempts >= maxAttempts) {
              clearInterval(nextTimer);
            }
          }, interval);
        }, initialDelay);
      };
      const observeNextButton = () => {
        if (window.__codexbarNextObserver || !window.MutationObserver) return;
        const observer = new MutationObserver(() => {
          if (clickNextIfReady()) {
            observer.disconnect();
            window.__codexbarNextObserver = null;
          }
        });
        observer.observe(document.body, { subtree: true, childList: true, attributes: true });
        window.__codexbarNextObserver = observer;
      };
      const findCreditsCardButton = () => {
        const nodes = Array.from(document.querySelectorAll('h1,h2,h3,div,span,p'));
        const labelMatch = nodes.find(node => {
          const lower = textOf(node).toLowerCase();
          return lower === 'credits remaining' || (lower.includes('credits') && lower.includes('remaining'));
        });
        if (!labelMatch) return null;
        let cur = labelMatch;
        for (let i = 0; i < 6 && cur; i++) {
        const buttons = Array.from(cur.querySelectorAll(buttonSelector));
        const picked = pickLikelyButton(buttons);
        if (picked) return picked;
        cur = cur.parentElement;
      }
        return null;
      };
      const findAndClick = () => {
        const addMoreButton = findAddMoreButton();
        if (addMoreButton) {
          clickButton(addMoreButton);
          return true;
        }
        const cardButton = findCreditsCardButton();
        if (!cardButton) return false;
        return clickButton(cardButton);
      };
      if (findAndClick()) {
        window.__codexbarAutoBuyCreditsStarted = true;
        startNextPolling();
        observeNextButton();
        return 'clicked';
      }
      startNextPolling(500);
      observeNextButton();
      let attempts = 0;
      const maxAttempts = 14;
      const timer = setInterval(() => {
        attempts += 1;
        if (findAndClick()) {
          startNextPolling();
          clearInterval(timer);
          return;
        }
        if (attempts >= maxAttempts) {
          clearInterval(timer);
        }
      }, 500);
      window.__codexbarAutoBuyCreditsStarted = true;
      return 'scheduled';
    })();
    """

    private let logger = Logger(subsystem: "com.steipete.codexbar", category: "creditsPurchase")
    private var webView: WKWebView?
    private var accountEmail: String?
    private var pendingAutoStart = false

    init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(purchaseURL: URL, accountEmail: String?, autoStartPurchase: Bool) {
        let normalizedEmail = Self.normalizeEmail(accountEmail)
        if self.window == nil || normalizedEmail != self.accountEmail {
            self.accountEmail = normalizedEmail
            self.buildWindow()
        }
        self.pendingAutoStart = autoStartPurchase
        self.load(url: purchaseURL)
        self.window?.center()
        self.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = OpenAIDashboardWebsiteDataStore.store(forAccountEmail: self.accountEmail)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: .zero)
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let window = NSWindow(
            contentRect: Self.defaultFrame(),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false)
        window.title = "Buy Credits"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentView = container
        window.center()

        self.window = window
        self.webView = webView
    }

    private func load(url: URL) {
        guard let webView else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.pendingAutoStart else { return }
        self.pendingAutoStart = false
        webView.evaluateJavaScript(Self.autoStartScript) { [logger] result, error in
            if let error {
                logger.debug("Auto-start purchase failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            if let result {
                logger.debug("Auto-start purchase result: \(String(describing: result), privacy: .public)")
            }
        }
    }

    private static func normalizeEmail(_ email: String?) -> String? {
        guard let raw = email?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw.lowercased()
    }

    private static func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 900)
        let width = min(Self.defaultSize.width, visible.width * 0.92)
        let height = min(Self.defaultSize.height, visible.height * 0.88)
        let origin = NSPoint(x: visible.midX - width / 2, y: visible.midY - height / 2)
        return NSRect(origin: origin, size: NSSize(width: width, height: height))
    }
}
