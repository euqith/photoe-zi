import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var oauthNavController: UINavigationController?
  private var pendingResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(name: "com.photoezi/oauth_popup", binaryMessenger: messenger)

    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      switch call.method {
      case "openOAuthPopup":
        guard let args = call.arguments as? [String: Any],
              let urlStr = args["url"] as? String,
              let url = URL(string: urlStr) else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing OAuth URL", details: nil))
          return
        }
        let redirectPrefix = (args["redirectPrefix"] as? String) ?? "http://127.0.0.1"
        self.presentOAuthSheet(url: url, redirectPrefix: redirectPrefix, flutterResult: result)

      case "closeOAuthPopup":
        self.dismissOAuthSheet(callbackUrl: nil, notifyCancel: false)
        result(true)

      case "openExternalUrl":
        if let args = call.arguments as? [String: Any],
           let urlStr = args["url"] as? String,
           let url = URL(string: urlStr) {
          UIApplication.shared.open(url, options: [:], completionHandler: nil)
          result(true)
        } else {
          result(false)
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let keyWindow = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow }) ?? scenes.flatMap { $0.windows }.first
    var top = keyWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func presentOAuthSheet(url: URL, redirectPrefix: String, flutterResult: @escaping FlutterResult) {
    if oauthNavController != nil {
      dismissOAuthSheet(callbackUrl: nil, notifyCancel: true)
    }

    guard let presenter = topViewController() else {
      flutterResult(FlutterError(code: "NO_VIEW_CONTROLLER", message: "No active iOS view controller", details: nil))
      return
    }

    self.pendingResult = flutterResult

    let oauthVC = IOSOAuthPopupViewController(
      authUrl: url,
      redirectPrefix: redirectPrefix,
      onComplete: { [weak self] callbackUrl in
        self?.dismissOAuthSheet(callbackUrl: callbackUrl, notifyCancel: false)
      },
      onCancel: { [weak self] in
        self?.dismissOAuthSheet(callbackUrl: nil, notifyCancel: true)
      }
    )

    let nav = UINavigationController(rootViewController: oauthVC)
    nav.modalPresentationStyle = .pageSheet
    nav.overrideUserInterfaceStyle = .dark
    nav.presentationController?.delegate = oauthVC
    self.oauthNavController = nav

    presenter.present(nav, animated: true, completion: nil)
  }

  private func dismissOAuthSheet(callbackUrl: String?, notifyCancel: Bool) {
    let callback = pendingResult
    pendingResult = nil
    let nav = oauthNavController
    oauthNavController = nil

    DispatchQueue.main.async {
      nav?.dismiss(animated: true, completion: nil)
      if let url = callbackUrl {
        callback?(url)
      } else if notifyCancel {
        callback?(nil)
      }
    }
  }
}

class IOSOAuthPopupViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIAdaptivePresentationControllerDelegate {
  private let authUrl: URL
  private let redirectPrefix: String
  private let onComplete: (String) -> Void
  private let onCancel: () -> Void
  private var webView: WKWebView!
  private var activityIndicator: UIActivityIndicatorView!
  private var hasFinished = false

  init(
    authUrl: URL,
    redirectPrefix: String,
    onComplete: @escaping (String) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.authUrl = authUrl
    self.redirectPrefix = redirectPrefix
    self.onComplete = onComplete
    self.onCancel = onCancel
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1.0)
    title = "Sign in with Google"

    navigationItem.leftBarButtonItem = UIBarButtonItem(
      barButtonSystemItem: .cancel,
      target: self,
      action: #selector(handleCancelTap)
    )
    navigationItem.leftBarButtonItem?.tintColor = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)

    let config = WKWebViewConfiguration()
    config.websiteDataStore = WKWebsiteDataStore.default()
    webView = WKWebView(frame: view.bounds, configuration: config)
    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    webView.navigationDelegate = self
    webView.uiDelegate = self
    // Standard iOS Safari Mobile User-Agent so Google OAuth 2.0 allows sign-in inside the popup sheet
    webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    activityIndicator = UIActivityIndicatorView(style: .medium)
    activityIndicator.color = UIColor(red: 0.96, green: 0.62, blue: 0.04, alpha: 1.0)
    activityIndicator.center = view.center
    activityIndicator.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
    activityIndicator.hidesWhenStopped = true
    activityIndicator.startAnimating()

    view.addSubview(webView)
    view.addSubview(activityIndicator)

    webView.load(URLRequest(url: authUrl))
  }

  @objc private func handleCancelTap() {
    guard !hasFinished else { return }
    hasFinished = true
    onCancel()
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard !hasFinished else { return }
    hasFinished = true
    onCancel()
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
      guard !hasFinished else { return }
      hasFinished = true
      onComplete(targetUrl.absoluteString)
      return
    }
    decisionHandler(.allow)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    activityIndicator.stopAnimating()
    if let currentUrl = webView.url, isLoopbackRedirect(currentUrl) {
      guard !hasFinished else { return }
      hasFinished = true
      onComplete(currentUrl.absoluteString)
    }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    activityIndicator.stopAnimating()
  }
}
