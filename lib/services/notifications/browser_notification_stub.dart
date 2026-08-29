import 'package:flutter/services.dart';

class BrowserNotificationPlatform {
  static const _channel = MethodChannel('wattly/notifications');

  bool get isSupported => true;
  bool get isGranted => true;

  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  void show({required String title, required String body}) {
    _channel.invokeMethod<void>('show', {'title': title, 'body': body});
  }
}
