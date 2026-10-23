import 'package:flutter/services.dart';

/// Cầu nối sang code Kotlin: nhắc nhở định kỳ + lưu file CSV.
class NativeBridge {
  static const _ch = MethodChannel('can_lo/native');

  static Future<void> setReminder({
    required bool enabled,
    required int hour,
    required int minute,
    required int daysMask,
  }) async {
    try {
      await _ch.invokeMethod('setReminder', {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'days': daysMask,
      });
    } on PlatformException catch (_) {}
  }

  static Future<bool> requestNotificationPermission() async {
    try {
      return (await _ch.invokeMethod<bool>('requestNotificationPermission')) ??
          true;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Mở hộp thoại "Lưu thành" của Android. Trả về true nếu đã lưu.
  static Future<bool> saveTextFile(String fileName, String content) async {
    final ok = await _ch.invokeMethod<bool>(
        'saveFile', {'name': fileName, 'content': content});
    return ok ?? false;
  }
}
