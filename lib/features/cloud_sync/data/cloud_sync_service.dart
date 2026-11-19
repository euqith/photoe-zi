enum UploadStatus { pending, bakingLut, uploading, completed, failed }

enum UploadVariant { bakedLut, original, both }

enum AutoUploadMode { all, favoritesOnly, manual }

class GoogleDriveAccount {
  final String email;
  final String displayName;
  final String? accessToken;
  final String scope;

  const GoogleDriveAccount({
    required this.email,
    required this.displayName,
    this.accessToken,
    this.scope = 'https://www.googleapis.com/auth/drive.file',
  });
}

abstract class CloudSyncService {
  static const String driveFileScope =
      'https://www.googleapis.com/auth/drive.file';

  bool get isSignedIn;
  GoogleDriveAccount? get currentUser;
  bool get isOffline;
  String? get customParentFolderId;

  Future<bool> signIn({String? email, String? accessToken});
  Future<void> signOut();
  void setCustomParentFolder(String? folderIdOrUrl);
  void setOfflineMode(bool offline);

  Future<String> createSessionFolder(String sessionName);
  Future<void> enqueuePhoto({
    required String localPhotoId,
    required String driveFolderId,
    required UploadVariant variant,
    String? activeLutId,
  });
  Future<void> retryFailedUploads();
  Future<String> generateShareableFolderLink(String driveFolderId);
  Stream<Map<String, double>> get uploadProgressStream;

  /// Parses either a full Google Drive folder URL
  /// (e.g. `https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp?usp=sharing`)
  /// or a raw folder ID and returns the clean Drive Folder ID.
  static String extractDriveFolderId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    final foldersMatch =
        RegExp(r'/folders/([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (foldersMatch != null) {
      return foldersMatch.group(1)!;
    }

    final idParamMatch = RegExp(r'[?&]id=([a-zA-Z0-9_-]+)').firstMatch(trimmed);
    if (idParamMatch != null) {
      return idParamMatch.group(1)!;
    }

    return trimmed;
  }

  /// Formats a clean shareable Google Drive folder URL from a folder ID or existing link.
  static String formatShareableUrl(String folderIdOrLink) {
    final trimmed = folderIdOrLink.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final cleanId = extractDriveFolderId(trimmed);
    if (cleanId.isEmpty) {
      return 'https://drive.google.com/drive/my-drive';
    }
    return 'https://drive.google.com/drive/folders/$cleanId?usp=sharing';
  }
}
