enum UploadStatus { pending, bakingLut, uploading, completed, failed }

enum UploadVariant { bakedLut, original, both }

abstract class CloudSyncService {
  Future<bool> signIn();
  Future<void> signOut();
  Future<String> createSessionFolder(String sessionName);
  Future<void> enqueuePhoto({
    required String localPhotoId,
    required String driveFolderId,
    required UploadVariant variant,
    String? activeLutId,
  });
  Future<String> generateShareableFolderLink(String driveFolderId);
  Stream<Map<String, double>> get uploadProgressStream;
}

