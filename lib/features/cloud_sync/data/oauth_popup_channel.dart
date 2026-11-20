import 'dart:io';

import 'package:flutter/services.dart';

/// Cross-platform native OAuth 2.0 Popup Window channel for iOS, Android, and macOS.
///
/// Opens an in-app native popup sheet/window (WKWebView on iOS/macOS, WebView on Android)
/// with a standard browser User-Agent so Google Sign-In works inside a self-contained popup
/// and automatically closes the instant Google redirects to the loopback redirect URI.
class OAuthPopupChannel {
  static const MethodChannel _channel =
      MethodChannel('com.photoezi/oauth_popup');

  /// Opens a native popup window for Google OAuth 2.0 login and returns the final
  /// redirect callback URL (e.g. `http://127.0.0.1:53682/?code=...`), or `null`
  /// if the user closed/cancelled the popup.
  ///
  /// Throws [MissingPluginException] if running in a headless unit test or unsupported host.
  static Future<String?> openOAuthPopup({
    required String authUrl,
    required String redirectUriPrefix,
  }) async {
    final result = await _channel.invokeMethod<String>('openOAuthPopup', {
      'url': authUrl,
      'redirectPrefix': redirectUriPrefix,
    });
    return result;
  }

  /// Explicitly closes any active native OAuth popup window.
  static Future<void> closeOAuthPopup() async {
    try {
      await _channel.invokeMethod<void>('closeOAuthPopup');
    } catch (_) {}
  }

  /// Opens an external URL in the system browser across iOS, Android, macOS, Windows, and Linux.
  static Future<void> openExternalUrl(String url) async {
    try {
      final handled = await _channel.invokeMethod<bool>('openExternalUrl', {
        'url': url,
      });
      if (handled == true) return;
    } catch (_) {}

    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      }
    } catch (_) {}
  }
}
