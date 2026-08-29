import 'file_download_stub.dart'
    if (dart.library.html) 'file_download_web.dart';

class FileDownloadService {
  final FileDownloadPlatform _platform = FileDownloadPlatform();

  void downloadText({
    required String filename,
    required String content,
    String mimeType = 'text/plain;charset=utf-8',
  }) {
    _platform.downloadText(
      filename: filename,
      content: content,
      mimeType: mimeType,
    );
  }
}
