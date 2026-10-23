import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'models.dart';
import 'protocols.dart';

/// Thiết bị bắt được khi quét (dùng cho màn khám phá + dò byte).
class SeenDevice {
  final String id;
  String name;
  int rssi;
  DateTime lastSeen;
  bool connectable;
  AdvPacket packet;
  final Map<String, List<int>> prev = {};
  int packets = 0;
  /// Các gói gần đây, dùng để chấm điểm vị trí byte khi dò cân lạ.
  final List<(DateTime, AdvPacket)> recent = [];

  SeenDevice(this.id, this.name, this.rssi, this.lastSeen, this.connectable,
      this.packet);

  /// Vị trí byte đã thay đổi so với gói trước, theo từng luồng.
  Set<int> changed(String key) {
    final cur = packet.streams[key];
    final old = prev[key];
    if (cur == null || old == null) return {};
    final s = <int>{};
    for (var i = 0; i < cur.length; i++) {
      if (i >= old.length || old[i] != cur[i]) s.add(i);
    }
    return s;
  }
}

enum LinkState { idle, listening, lost, connecting, connected, syncing, error }

class DeviceLink {
  LinkState state = LinkState.idle;
  String? error;
  DateTime? lastPacket;
  double? lastKg; // số đọc được gần nhất, để người dùng thấy app đang nghe đúng cân
  int failures = 0;
  DateTime nextTry = DateTime.fromMillisecondsSinceEpoch(0);
  bool busy = false;
  StreamSubscription? connSub;
  StreamSubscription? valueSub;
}

typedef ReadingHandler = void Function(String deviceId, Reading r,
    {required bool fromGatt});
typedef RemapHandler = void Function(String oldId, SavedDevice device);

class BleService extends ChangeNotifier {
  BluetoothAdapterState adapter = BluetoothAdapterState.unknown;
  bool scanning = false;
  bool supported = true;
  String? scanError;

  final Map<String, SeenDevice> seen = {};
  final Map<String, DeviceLink> links = {};
  Map<String, SavedDevice> watched = {};
  ReadingHandler? onReading;
  /// Cân đổi địa chỉ Bluetooth (nhiều cân rẻ đổi sau mỗi lần thức dậy).
  RemapHandler? onRemap;
  DateTime? _scanStartedAt;

  StreamSubscription? _adapterSub, _scanSub, _isScanSub;
  Timer? _tick;
  bool _dirty = false;
  bool _wantScan = false;

  Future<void> init() async {
    try {
      await FlutterBluePlus.setLogLevel(LogLevel.warning, color: false);
    } catch (_) {}
    supported = await FlutterBluePlus.isSupported;
    if (!supported) {
      notifyListeners();
      return;
    }
    _adapterSub = FlutterBluePlus.adapterState.listen((s) {
      adapter = s;
      if (s == BluetoothAdapterState.on && _wantScan && !scanning) {
        startScan();
      }
      if (s != BluetoothAdapterState.on) {
        for (final l in links.values) {
          l.state = LinkState.idle;
        }
      }
      notifyListeners();
    });
    _isScanSub = FlutterBluePlus.isScanning.listen((v) {
      scanning = v;
      notifyListeners();
    });
    _scanSub = FlutterBluePlus.onScanResults.listen(_onResults,
        onError: (e) => _setError(e));
    // Gom cập nhật UI + kiểm tra mất tín hiệu mỗi 300ms.
    _tick = Timer.periodic(const Duration(milliseconds: 300), (_) {
      final now = DateTime.now();
      for (final e in links.entries) {
        final l = e.value;
        if (l.state == LinkState.listening &&
            l.lastPacket != null &&
            now.difference(l.lastPacket!) > const Duration(seconds: 12)) {
          l.state = LinkState.lost;
          _dirty = true;
        }
      }
      // Android tự hạ cấp lượt quét không lọc sau khoảng 30 phút, nên quét lại.
      final st = _scanStartedAt;
      if (scanning && _wantScan && st != null &&
          now.difference(st) > const Duration(minutes: 20)) {
        _scanStartedAt = null;
        stopScan(keepWanted: true).then((_) => startScan());
      }
      if (_dirty) {
        _dirty = false;
        notifyListeners();
      }
    });
  }

  void setWatched(List<SavedDevice> devices) {
    watched = {for (final d in devices) d.id: d};
    links.removeWhere((id, l) {
      if (watched.containsKey(id)) return false;
      l.connSub?.cancel();
      l.valueSub?.cancel();
      return true;
    });
    for (final d in devices) {
      links.putIfAbsent(d.id, () => DeviceLink());
    }
    notifyListeners();
  }

  Future<void> turnOn() async {
    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        _setError(e);
      }
    }
  }

  Future<void> startScan() async {
    _wantScan = true;
    if (!supported) return;
    if (adapter != BluetoothAdapterState.on) {
      scanError = null;
      notifyListeners();
      return;
    }
    if (FlutterBluePlus.isScanningNow) return;
    try {
      scanError = null;
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        androidScanMode: AndroidScanMode.lowLatency,
      );
      _scanStartedAt = DateTime.now();
      for (final l in links.values) {
        if (l.state == LinkState.idle) l.state = LinkState.listening;
      }
    } catch (e) {
      _setError(e);
    }
    notifyListeners();
  }

  Future<void> stopScan({bool keepWanted = false}) async {
    if (!keepWanted) _wantScan = false;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }

  final Map<String, DateTime> _lastTs = {};

  void _onResults(List<ScanResult> results) {
    for (final r in results) {
      final id = r.device.remoteId.str;
      final last = _lastTs[id];
      if (last != null && !r.timeStamp.isAfter(last)) continue;
      _lastTs[id] = r.timeStamp;

      final ad = r.advertisementData;
      final svc = <String, List<int>>{};
      ad.serviceData.forEach((g, v) => svc[normUuid(g.toString())] = v);
      final packet = AdvPacket(
        Map<int, List<int>>.from(ad.manufacturerData),
        svc,
        ad.serviceUuids.map((g) => normUuid(g.toString())).toList(),
      );
      final name = ad.advName.isNotEmpty
          ? ad.advName
          : (r.device.platformName.isNotEmpty ? r.device.platformName : '');

      final s = seen[id];
      if (s == null) {
        seen[id] = SeenDevice(id, name, r.rssi, DateTime.now(),
            ad.connectable, packet)
          ..packets = 1;
      } else {
        // Chỉ lưu "gói trước" khi nội dung thật sự đổi, để tô byte thay đổi.
        packet.streams.forEach((k, v) {
          final old = s.packet.streams[k];
          if (old != null && !listEquals(old, v)) s.prev[k] = old;
        });
        s.packet = packet;
        if (name.isNotEmpty) s.name = name;
        s.rssi = r.rssi;
        s.lastSeen = DateTime.now();
        s.connectable = ad.connectable;
        s.packets++;
      }
      final sd = seen[id]!;
      sd.recent.add((DateTime.now(), packet));
      if (sd.recent.length > 60) sd.recent.removeAt(0);

      var dev = watched[id];
      dev ??= _remapIfSameScale(id, name, packet);
      if (dev != null) _handleWatched(dev, packet);
    }
    _dirty = true;
  }

  /// Gói từ địa chỉ lạ nhưng giống hệt "dấu vân tay" một cân đã lưu mà
  /// lâu không nghe thấy: coi là cân đó vừa đổi địa chỉ.
  SavedDevice? _remapIfSameScale(String id, String name, AdvPacket packet) {
    final now = DateTime.now();
    for (final d in watched.values) {
      if (d.proto.needsConnection) continue;
      final last = links[d.id]?.lastPacket;
      if (last != null && now.difference(last) < const Duration(seconds: 20)) {
        continue; // cân cũ vẫn đang phát, không phải nó
      }
      final fp = (d.config['fp'] as Map?)?.cast<String, dynamic>();
      if (!matchesFingerprint(fp, name, packet)) continue;
      if (parseAdv(d, packet) == null) continue;
      final oldId = d.id;
      final link = links.remove(oldId) ?? DeviceLink();
      watched.remove(oldId);
      d.id = id;
      watched[id] = d;
      links[id] = link;
      onRemap?.call(oldId, d);
      return d;
    }
    return null;
  }

  void _handleWatched(SavedDevice dev, AdvPacket packet) {
    final link = links.putIfAbsent(dev.id, () => DeviceLink());
    link.lastPacket = DateTime.now();
    if (dev.proto.needsConnection) {
      _ensureGatt(dev, link);
      return;
    }
    if (link.state != LinkState.listening) {
      link.state = LinkState.listening;
      link.error = null;
    }
    final reading = parseAdv(dev, packet);
    if (reading != null) {
      link.lastKg = reading.kg;
      onReading?.call(dev.id, reading, fromGatt: false);
    }
  }

  Future<void> _ensureGatt(SavedDevice dev, DeviceLink link) async {
    if (link.busy ||
        link.state == LinkState.connected ||
        link.state == LinkState.syncing) {
      return;
    }
    if (DateTime.now().isBefore(link.nextTry)) return;
    link.busy = true;
    link.state = LinkState.connecting;
    link.error = null;
    _dirty = true;
    final device = BluetoothDevice.fromId(dev.id);
    try {
      link.connSub ??= device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected &&
            (link.state == LinkState.connected ||
                link.state == LinkState.syncing)) {
          link.state = LinkState.listening;
          link.valueSub?.cancel();
          link.valueSub = null;
          _dirty = true;
        }
      });
      await device.connect(
          timeout: const Duration(seconds: 15), autoConnect: false);
      link.state = LinkState.syncing;
      _dirty = true;
      final services = await device.discoverServices();
      BluetoothCharacteristic? wm;
      for (final s in services) {
        if (normUuid(s.uuid.toString()) != svcWeightScale) continue;
        for (final c in s.characteristics) {
          if (normUuid(c.uuid.toString()) == chrWeightMeasurement) wm = c;
        }
      }
      if (wm == null) {
        throw Exception(
            'Cân không có dịch vụ Weight Scale chuẩn. Thử chế độ "Tự dò byte".');
      }
      await link.valueSub?.cancel();
      link.valueSub = wm.onValueReceived.listen((v) {
        final r = parseWeightMeasurement(v);
        if (r != null) onReading?.call(dev.id, r, fromGatt: true);
      });
      await wm.setNotifyValue(true);
      link.failures = 0;
      link.state = LinkState.connected;
    } catch (e) {
      link.failures++;
      final wait = min(60, 2 << min(link.failures, 5));
      link.nextTry = DateTime.now().add(Duration(seconds: wait));
      link.state = LinkState.error;
      link.error = _friendly(e);
      try {
        await device.disconnect();
      } catch (_) {}
    } finally {
      link.busy = false;
      _dirty = true;
    }
  }

  Future<void> retry(String id) async {
    final link = links[id];
    if (link == null) return;
    link.failures = 0;
    link.nextTry = DateTime.fromMillisecondsSinceEpoch(0);
    link.state = LinkState.listening;
    link.error = null;
    notifyListeners();
    if (!scanning) await startScan();
  }

  Future<void> disconnect(String id) async {
    final l = links[id];
    await l?.valueSub?.cancel();
    if (l != null) l.valueSub = null;
    try {
      await BluetoothDevice.fromId(id).disconnect();
    } catch (_) {}
  }

  void _setError(Object e) {
    scanError = _friendly(e);
    _dirty = true;
    notifyListeners();
  }

  String _friendly(Object e) {
    final s = e.toString();
    final low = s.toLowerCase();
    if (low.contains('permission')) {
      return 'Thiếu quyền Bluetooth. Vào Cài đặt điện thoại > Ứng dụng > Cân Lỏ > Quyền, bật "Thiết bị ở gần".';
    }
    if (low.contains('location')) {
      return 'Android bản cũ cần bật Vị trí (GPS) để quét Bluetooth.';
    }
    if (low.contains('timeout') || low.contains('timed out')) {
      return 'Kết nối quá lâu không phản hồi. Bước lên cân cho nó thức rồi thử lại.';
    }
    if (low.contains('scan') && low.contains('frequently')) {
      return 'Quét lại quá nhanh, Android đang tạm chặn. Đợi 30 giây.';
    }
    return s.replaceFirst('Exception: ', '');
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _scanSub?.cancel();
    _isScanSub?.cancel();
    _tick?.cancel();
    for (final l in links.values) {
      l.connSub?.cancel();
      l.valueSub?.cancel();
    }
    super.dispose();
  }
}
