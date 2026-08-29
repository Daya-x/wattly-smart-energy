class FileDownloadPlatform {
  void downloadText({
    required String filename,
    required String content,
    required String mimeType,
  }) {
    throw UnsupportedError('File downloads are only available in the browser.');
  }
}
