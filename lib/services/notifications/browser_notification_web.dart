// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

class BrowserNotificationPlatform {
  bool get isSupported => html.Notification.supported;
  bool get isGranted => html.Notification.permission == 'granted';

  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    if (isGranted) return true;
    return await html.Notification.requestPermission() == 'granted';
  }

  void show({required String title, required String body}) {
    if (!isGranted) return;
    html.Notification(title, body: body);
  }
}
