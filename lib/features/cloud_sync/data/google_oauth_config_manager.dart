import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class GoogleOAuthConfig {
  final String clientId;
  final String clientSecret;
  final String appName;

  const GoogleOAuthConfig({
    this.clientId = '',
    this.clientSecret = '',
    this.appName = 'PhotoE-Zi',
  });

  bool get isConfigured => clientId.trim().isNotEmpty;

  String get maskedClientId {
    final clean = clientId.trim();
    if (clean.length <= 16) return clean;
    final prefix = clean.substring(0, 8);
    final suffix = clean.substring(clean.length - 8);
    return '$prefix...$suffix';
  }

  Map<String, dynamic> toJson() => {
        'clientId': clientId.trim(),
        'clientSecret': clientSecret.trim(),
        'appName': appName.trim(),
      };

  factory GoogleOAuthConfig.fromJson(Map<String, dynamic> json) =>
      GoogleOAuthConfig(
        clientId: json['clientId']?.toString() ?? '',
        clientSecret: json['clientSecret']?.toString() ?? '',
        appName: json['appName']?.toString() ?? 'PhotoE-Zi',
      );
}

class GoogleOAuthConfigManager {
  static const String envClientId = String.fromEnvironment(
    'PHOTOE_ZI_GDRIVE_CLIENT_ID',
    defaultValue: '',
  );
  static const String envClientSecret = String.fromEnvironment(
    'PHOTOE_ZI_GDRIVE_CLIENT_SECRET',
    defaultValue: '',
  );

  final Future<Directory> Function()? configDirProvider;
  final bool allowDefaultFallback;
  GoogleOAuthConfig? _cachedConfig;

  GoogleOAuthConfigManager({
    this.configDirProvider,
    this.allowDefaultFallback = true,
  });

  Future<File> _resolveConfigFile() async {
    Directory dir;
    if (configDirProvider != null) {
      dir = await configDirProvider!();
    } else {
      try {
        dir = await getApplicationSupportDirectory();
      } catch (_) {
        dir = Directory(
            p.join(Directory.systemTemp.path, 'photoe_zi_auth_config'));
      }
    }
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'photoe_zi_oauth_config.json'));
  }

  Future<GoogleOAuthConfig> loadConfig() async {
    if (_cachedConfig != null && _cachedConfig!.isConfigured) {
      return _cachedConfig!;
    }

    // 1. Check local persistent config file first
    try {
      final file = await _resolveConfigFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          final config = GoogleOAuthConfig.fromJson(json);
          if (config.isConfigured) {
            _cachedConfig = config;
            return config;
          }
        }
      }
    } catch (_) {}

    // 2. Check compile-time environment variables
    if (envClientId.trim().isNotEmpty) {
      final envConfig = GoogleOAuthConfig(
        clientId: envClientId.trim(),
        clientSecret: envClientSecret.trim(),
      );
      _cachedConfig = envConfig;
      return envConfig;
    }

    // 3. Check bundled app asset config (assets/config/photoe_zi_default_oauth.json)
    if (allowDefaultFallback) {
      try {
        final assetJsonStr = await rootBundle.loadString(
          'assets/config/photoe_zi_default_oauth.json',
        );
        if (assetJsonStr.trim().isNotEmpty) {
          final json = jsonDecode(assetJsonStr) as Map<String, dynamic>;
          final assetConfig = GoogleOAuthConfig.fromJson(json);
          if (assetConfig.isConfigured) {
            _cachedConfig = assetConfig;
            return assetConfig;
          }
        }
      } catch (_) {}
    }

    return const GoogleOAuthConfig();
  }

  Future<GoogleOAuthConfig> saveConfig({
    required String clientId,
    String? clientSecret,
    String appName = 'PhotoE-Zi',
  }) async {
    final cleanClient = clientId.trim();
    final cleanSecret = (clientSecret ?? '').trim();
    final newConfig = GoogleOAuthConfig(
      clientId: cleanClient,
      clientSecret: cleanSecret,
      appName: appName,
    );

    try {
      final file = await _resolveConfigFile();
      await file.writeAsString(
        jsonEncode(newConfig.toJson()),
        flush: true,
      );
    } catch (_) {}

    _cachedConfig = newConfig;
    return newConfig;
  }

  Future<void> clearConfig() async {
    _cachedConfig = null;
    try {
      final file = await _resolveConfigFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
