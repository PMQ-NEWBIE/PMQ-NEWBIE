import 'dart:convert';

import 'package:flutter/services.dart';

/// Một lần cân do dịch vụ chạy nền ghi lại, chờ app nhập vào lịch sử.
class BgReading {
  final String deviceId;
  final double kg;
  final DateTime at;
  final int? impedance;
  final String? method;
  final int? samples;
  final int? durationMs;
  final double? minKg;
  final double? maxKg;
  final String? raw;

  BgReading(this.deviceId, this.kg, this.at,
      {this.impedance,
      this.method,
      this.samples,
      this.durationMs,
      this.minKg,
      this.maxKg,
      this.raw});

  static BgReading? fromJson(Map<String, dynamic> j) {
    final id = j['deviceId'] as String?;
    final kg = (j['kg'] as num?)?.toDouble();
    final at = (j['at'] as num?)?.toInt();
    if (id == null || kg == null || at == null) return null;
    return BgReading(
      id,
      kg,
      DateTime.fromMillisecondsSinceEpoch(at),
      impedance: (j['imp'] as num?)?.toInt(),
      method: j['method'] as String?,
      samples: (j['samples'] as num?)?.toInt(),
      durationMs: (j['durationMs'] as num?)?.toInt(),
      minKg: (j['minKg'] as num?)?.toDouble(),
      maxKg: (j['maxKg'] as num?)?.toDouble(),
      raw: j['raw'] as String?,
    );
  }
}

class BgStatus {
  final bool running;
  final bool batteryUnrestricted;
  final String? error;
  const BgStatus(this.running, this.batteryUnrestricted, this.error);
}

/// Cầu nối sang code Kotlin: chạy nền, nhắc nhở, lưu file.
class NativeBridge {
  static const _ch = MethodChannel('can_lo/native');

  static Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException catch (_) {
      return null;
    } on MissingPluginException catch (_) {
      return null;
    }
  }

  static Future<void> setReminder({
    required bool enabled,
    required int hour,
    required int minute,
    required int daysMask,
  }) =>
      _call('setReminder', {
        'enabled': enabled,
        'hour': hour,
        'minute': minute,
        'days': daysMask,
      });

  static Future<bool> requestNotificationPermission() async =>
      (await _call<bool>('requestNotificationPermission')) ?? false;

  /// Mở hộp thoại "Lưu thành" của Android. Trả về true nếu đã lưu.
  static Future<bool> saveTextFile(String fileName, String content) async {
    final ok = await _ch.invokeMethod<bool>(
        'saveFile', {'name': fileName, 'content': content});
    return ok ?? false;
  }

  static Future<void> configureBackground({
    required bool enabled,
    required List<Map<String, Object?>> devices,
    required bool unitLb,
  }) =>
      _call('configureBackground', {
        'enabled': enabled,
        'devices': jsonEncode(devices),
        'lb': unitLb,
      });

  static Future<void> setAppForeground(bool v) =>
      _call('setAppForeground', {'value': v});

  static Future<List<BgReading>> drainBackground() async {
    final s = await _call<String>('drainBackground');
    if (s == null || s.isEmpty) return [];
    try {
      final list = jsonDecode(s) as List;
      return list
          .whereType<Map>()
          .map((e) => BgReading.fromJson(e.cast<String, dynamic>()))
          .whereType<BgReading>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<BgStatus> backgroundStatus() async {
    final m = await _call<Map>('backgroundStatus');
    if (m == null) return const BgStatus(false, false, null);
    return BgStatus(
      m['running'] == true,
      m['batteryUnrestricted'] == true,
      m['error'] as String?,
    );
  }

  static Future<void> requestBatteryUnrestricted() =>
      _call('requestBatteryUnrestricted');
}
