import Cocoa
import FlutterMacOS
import WebKit

class MainFlutterWindow: NSWindow, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
  private var oauthPopupWindow: NSWindow?
  private var oauthWebView: WKWebView?
  private var oauthProgressIndicator: NSProgressIndicator?
  private var pendingOAuthResult: FlutterResult?
  private var redirectPrefix: String = "http://127.0.0.1"
  private var isOAuthCompleted: Bool = false
  private var cameraBridgeManager: CameraBridgeManager?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    cameraBridgeManager = CameraBridgeManager(messenger: flutterViewController.engine.binaryMessenger)

    let oauthChannel = FlutterMethodChannel(
      name: "com.photoezi/oauth_popup",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    oauthChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "openOAuthPopup":
        guard let args = call.arguments as? [String: Any],
              let urlStr = args["url"] as? String,
              let url = URL(string: urlStr) else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing OAuth URL", details: nil))
          return
        }
        let prefix = (args["redirectPrefix"] as? String) ?? "http://127.0.0.1"
        self.presentOAuthPopup(url: url, redirectPrefix: prefix, flutterResult: result)

      case "closeOAuthPopup":
        self.closeActiveOAuthPopup(cancelled: false)
        result(true)

      case "openExternalUrl":
        if let args = call.arguments as? [String: Any],
           let urlStr = args["url"] as? String,
           let url = URL(string: urlStr) {
          NSWorkspace.shared.open(url)
          result(true)
        } else {
          result(false)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func presentOAuthPopup(url: URL, redirectPrefix: String, flutterResult: @escaping FlutterResult) {
    // Clean up any existing popup first
    if oauthPopupWindow != nil {
      closeActiveOAuthPopup(cancelled: true)
    }

    self.redirectPrefix = redirectPrefix
    self.pendingOAuthResult = flutterResult
    self.isOAuthCompleted = false

    let popupWidth: CGFloat = 480
    let popupHeight: CGFloat = 650

    let parentFrame = self.frame
    let originX = parentFrame.origin.x + (parentFrame.size.width - popupWidth) / 2
    let originY = parentFrame.origin.y + (parentFrame.size.height - popupHeight) / 2
    let popupRect = NSRect(x: max(40, originX), y: max(40, originY), width: popupWidth, height: popupHeight)

    let popup = NSWindow(
      contentRect: popupRect,
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    popup.title = "Sign in with Google — PhotoE-Zi"
    popup.appearance = NSAppearance(named: .darkAqua)
    popup.backgroundColor = NSColor(calibratedRed: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
    popup.isReleasedWhenClosed = false
    popup.delegate = self
    popup.level = .floating

    let containerView = NSView(frame: NSRect(x: 0, y: 0, width: popupWidth, height: popupHeight))
    containerView.autoresizingMask = [.width, .height]

    let webConfig = WKWebViewConfiguration()
    webConfig.websiteDataStore = WKWebsiteDataStore.default()
    let webView = WKWebView(frame: containerView.bounds, configuration: webConfig)
    webView.autoresizingMask = [.width, .height]
    webView.navigationDelegate = self
    webView.uiDelegate = self
    // Standard macOS Safari User-Agent so Google OAuth 2.0 allows sign-in inside the popup
    webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    let spinner = NSProgressIndicator(frame: NSRect(x: (popupWidth - 28) / 2, y: (popupHeight - 28) / 2, width: 28, height: 28))
    spinner.style = .spinning
    spinner.controlSize = .regular
    spinner.isDisplayedWhenStopped = false
    spinner.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
    spinner.startAnimation(nil)

    containerView.addSubview(webView)
    containerView.addSubview(spinner)
    popup.contentView = containerView

    self.oauthPopupWindow = popup
    self.oauthWebView = webView
    self.oauthProgressIndicator = spinner

    popup.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    webView.load(URLRequest(url: url))
  }

  private func isLoopbackRedirect(_ url: URL) -> Bool {
    let abs = url.absoluteString
    if abs.hasPrefix(redirectPrefix) {
      return true
    }
    if let host = url.host?.lowercased(), (host == "127.0.0.1" || host == "localhost") {
      if abs.contains("code=") || abs.contains("error=") {
        return true
      }
    }
    return false
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if let targetUrl = navigationAction.request.url, isLoopbackRedirect(targetUrl) {
      decisionHandler(.cancel)
      completeOAuthWithCallback(url: targetUrl.absoluteString)
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    oauthProgressIndicator?.stopAnimation(nil)
    if let currentUrl = webView.url, isLoopbackRedirect(currentUrl) {
      completeOAuthWithCallback(url: currentUrl.absoluteString)
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    oauthProgressIndicator?.stopAnimation(nil)
  }

  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
      webView.load(URLRequest(url: url))
    }
    return nil
  }

  private func completeOAuthWithCallback(url: String) {
    guard !isOAuthCompleted else { return }
    isOAuthCompleted = true
    let callback = pendingOAuthResult
    pendingOAuthResult = nil

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.oauthWebView?.stopLoading()
      self.oauthPopupWindow?.delegate = nil
      self.oauthPopupWindow?.orderOut(nil)
      self.oauthPopupWindow?.close()
      self.oauthPopupWindow = nil
      self.oauthWebView = nil
      self.oauthProgressIndicator = nil
      self.makeKeyAndOrderFront(nil)
      callback?(url)
    }
  }

  private func closeActiveOAuthPopup(cancelled: Bool) {
    let callback = pendingOAuthResult
    pendingOAuthResult = nil
    isOAuthCompleted = true

    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.oauthWebView?.stopLoading()
      self.oauthPopupWindow?.delegate = nil
      self.oauthPopupWindow?.orderOut(nil)
      self.oauthPopupWindow?.close()
      self.oauthPopupWindow = nil
      self.oauthWebView = nil
      self.oauthProgressIndicator = nil
      if cancelled {
        callback?(nil)
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard let closingWindow = notification.object as? NSWindow,
          closingWindow == oauthPopupWindow else {
      return
    }
    if !isOAuthCompleted {
      isOAuthCompleted = true
      let callback = pendingOAuthResult
      pendingOAuthResult = nil
      oauthPopupWindow = nil
      oauthWebView = nil
      oauthProgressIndicator = nil
      callback?(nil)
    }
  }
}
