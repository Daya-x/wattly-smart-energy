import 'browser_notification_stub.dart'
    if (dart.library.html) 'browser_notification_web.dart';

class BrowserNotificationService {
  final BrowserNotificationPlatform _platform = BrowserNotificationPlatform();

  bool get isSupported => _platform.isSupported;
  bool get isGranted => _platform.isGranted;

  Future<bool> requestPermission() => _platform.requestPermission();

  void show({required String title, required String body}) {
    _platform.show(title: title, body: body);
  }
}
