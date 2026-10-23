import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../app_state.dart';
import '../ble_service.dart';
import '../fmt.dart';
import '../main.dart';
import '../models.dart';
import '../protocols.dart';
import '../widgets/common.dart';
import 'home_screen.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final _filter = TextEditingController();
  bool _onlyData = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.read(context).ble.startScan();
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Thiết bị')),
      body: ListenableBuilder(
        listenable: st.ble,
        builder: (context, _) {
          final ble = st.ble;
          final q = _filter.text.trim().toLowerCase();
          final saved = {for (final d in st.devices) d.id};
          final nearby = ble.seen.values
              .where((d) => !saved.contains(d.id))
              .where((d) =>
                  !_onlyData ||
                  d.packet.streams.isNotEmpty ||
                  d.packet.serviceUuids.isNotEmpty)
              .where((d) =>
                  q.isEmpty || d.name.toLowerCase().contains(q) || d.id.toLowerCase().contains(q))
              .where((d) =>
                  DateTime.now().difference(d.lastSeen) < const Duration(seconds: 30))
              .toList()
            // Thiết bị có vẻ là cân lên đầu, rồi tới sóng mạnh nhất.
            ..sort((a, b) {
              final sa = detectProto(a.packet) != null ? 1 : 0;
              final sb = detectProto(b.packet) != null ? 1 : 0;
              if (sa != sb) return sb - sa;
              return b.rssi.compareTo(a.rssi);
            });

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              MaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _scanBar(context, ble),
                    SectionTitle('Cân đã lưu (${st.devices.length})'),
                    if (st.devices.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'Chưa lưu cân nào. Bước lên cân cho nó sáng màn hình, cân sẽ hiện ở danh sách "Xung quanh" bên dưới, thường nằm trên cùng vì sóng mạnh nhất.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                    for (final d in st.devices) ...[
                      _savedCard(context, st, d),
                      const SizedBox(height: 8),
                    ],
                    SectionTitle('Xung quanh (${nearby.length})',
                        trailing: FilterChip(
                          label: const Text('Có dữ liệu'),
                          selected: _onlyData,
                          onSelected: (v) => setState(() => _onlyData = v),
                        )),
                    TextField(
                      controller: _filter,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Lọc theo tên hoặc địa chỉ',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (nearby.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(children: [
                          if (ble.scanning) const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(
                            ble.scanning
                                ? 'Đang dò sóng... bước lên cân để đánh thức nó'
                                : 'Bấm Quét để tìm thiết bị',
                            textAlign: TextAlign.center,
                          ),
                        ]),
                      ),
                    for (final d in nearby)
                      _NearbyTile(
                        d: d,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => AddDeviceScreen(deviceId: d.id))),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _scanBar(BuildContext context, BleService ble) {
    if (!ble.supported) {
      return const ErrorCard(
          title: 'Máy không hỗ trợ Bluetooth LE',
          message: 'App không dò được cân trên máy này.');
    }
    if (ble.adapter == BluetoothAdapterState.off) {
      return ErrorCard(
        title: 'Bluetooth đang tắt',
        message: 'Bật Bluetooth để quét cân.',
        actionLabel: 'Bật Bluetooth',
        onAction: ble.turnOn,
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ble.scanError != null) ...[
          ErrorCard(
            title: 'Không quét được',
            message: ble.scanError!,
            actionLabel: 'Thử lại',
            onAction: ble.startScan,
          ),
          const SizedBox(height: 8),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(children: [
              PulseDot(color: ble.scanning ? cs.primary : cs.outline, active: ble.scanning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(ble.scanning ? 'Đang quét Bluetooth' : 'Đã dừng quét',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              FilledButton.tonal(
                onPressed: ble.scanning ? () => ble.stopScan() : ble.startScan,
                child: Text(ble.scanning ? 'Dừng' : 'Quét'),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _savedCard(BuildContext context, AppState st, SavedDevice d) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DeviceStatusRow(
                      device: d, link: st.ble.links[d.id], scanning: st.ble.scanning),
                  Padding(
                    padding: const EdgeInsets.only(left: 30, bottom: 4),
                    child: Text(
                        '${d.proto.label} · ${d.id}'
                        '${st.ble.links[d.id]?.lastKg == null ? '' : ' · vừa đọc ${fmtWU(st.ble.links[d.id]!.lastKg!, st.unitLb)}'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'rename') {
                  final n = await _askName(context, d.name);
                  if (n != null) await st.renameDevice(d, n);
                } else if (v == 'retry') {
                  await st.ble.retry(d.id);
                } else if (v == 'remove') {
                  final ok = await confirmDialog(context,
                      title: 'Gỡ ${d.name}?',
                      message: 'Lịch sử cân vẫn giữ nguyên, chỉ ngừng nghe cân này.',
                      ok: 'Gỡ');
                  if (ok) await st.removeDevice(d.id);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'rename', child: Text('Đổi tên')),
                const PopupMenuItem(value: 'retry', child: Text('Kết nối lại')),
                const PopupMenuItem(value: 'remove', child: Text('Gỡ cân')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _askName(BuildContext context, String initial) async {
  final c = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Tên cân'),
      content: TextField(controller: c, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Lưu')),
      ],
    ),
  );
  if (r == null || r.isEmpty) return null;
  return r;
}

class _NearbyTile extends StatelessWidget {
  final SeenDevice d;
  final VoidCallback onTap;
  const _NearbyTile({required this.d, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final proto = detectProto(d.packet);
    final bars = d.rssi > -60 ? 3 : (d.rssi > -75 ? 2 : 1);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
            bars == 3
                ? Icons.signal_cellular_alt
                : (bars == 2
                    ? Icons.signal_cellular_alt_2_bar
                    : Icons.signal_cellular_alt_1_bar),
            color: cs.primary),
        title: Text(d.name.isEmpty ? '(không tên)' : d.name),
        subtitle: Text(
          '${d.rssi} dBm · ${d.packets} gói${proto != null ? ' · có vẻ là ${proto.label}' : ''}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: proto != null
            ? Icon(Icons.monitor_weight, color: cs.tertiary)
            : const Icon(Icons.chevron_right),
      ),
    );
  }
}

/// Màn thêm cân: xem byte thô, nhận diện kiểu cân, hoặc dò byte cho cân lạ.
class AddDeviceScreen extends StatefulWidget {
  final String deviceId;
  const AddDeviceScreen({super.key, required this.deviceId});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  final _known = TextEditingController();

  @override
  void dispose() {
    _known.dispose();
    super.dispose();
  }

  Future<void> _save(Proto proto, {Map<String, dynamic>? config, required String name}) async {
    final st = AppScope.read(context);
    final seen = st.ble.seen[widget.deviceId];
    final n = await _askName(context, name.isEmpty ? 'Cân nhà mình' : name);
    if (n == null || !mounted) return;
    final cfg = <String, dynamic>{...?config};
    // Lưu dấu vân tay để nhận ra cân kể cả khi nó đổi địa chỉ Bluetooth.
    if (seen != null) cfg['fp'] = fingerprintOf(seen.name, seen.packet);
    await st.addDevice(SavedDevice(id: widget.deviceId, name: n, proto: proto, config: cfg));
    if (!mounted) return;
    if (!proto.needsConnection && !st.backgroundOn) {
      final on = await confirmDialog(context,
          title: 'Ghi cả khi app đóng?',
          message:
              'Đã thêm $n. Từ giờ mở app là số tự lưu. Bật chạy nền thì cả lúc app đóng, bước lên cân cũng tự lưu và có thông báo.',
          ok: 'Bật chạy nền',
          danger: false);
      if (on) await st.setBackground(true);
    } else {
      toast(context, 'Đã thêm $n. Bước lên cân là số tự vào app.');
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Thêm cân')),
      body: ListenableBuilder(
        listenable: st.ble,
        builder: (context, _) {
          final d = st.ble.seen[widget.deviceId];
          if (d == null) {
            return const EmptyState(
                icon: Icons.bluetooth_searching,
                title: 'Mất sóng thiết bị',
                message: 'Bước lên cân lại để nó phát sóng.');
          }
          final proto = detectProto(d.packet);
          final known = double.tryParse(_known.text.replaceAll(',', '.'));
          final knownKg = known == null ? null : fromUnit(known, st.unitLb);
          final now = DateTime.now();
          final recent = d.recent
              .where((e) => now.difference(e.$1) < const Duration(seconds: 5))
              .map((e) => e.$2)
              .toList();
          int hits(Candidate c) => knownKg == null
              ? 0
              : recent.where((p) {
                  final r = parseLearned(p, c.cfg);
                  return r != null && (r.kg - knownKg).abs() <= 0.15;
                }).length;
          final cands = findCandidates(d.packet, knownKg).take(40).toList();
          final score = {for (final c in cands) c: hits(c)};
          cands.sort((a, b) {
            final h = score[b]!.compareTo(score[a]!);
            if (h != 0) return h;
            if (a.match != b.match) return a.match ? -1 : 1;
            return 0;
          });
          final age = DateTime.now().difference(d.lastSeen).inSeconds;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              MaxWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(d.name.isEmpty ? '(không tên)' : d.name,
                        style: t.textTheme.titleLarge),
                    Text('${d.id} · ${d.rssi} dBm · ${age < 2 ? 'đang phát' : 'gói cuối $age giây trước'}',
                        style: t.textTheme.bodySmall),
                    SectionTitle('Dữ liệu thô (byte đỏ = vừa đổi)'),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: d.packet.streams.isEmpty
                            ? const Text('Thiết bị này không phát dữ liệu kèm theo.')
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final e in d.packet.streams.entries)
                                    _HexLine(label: streamLabel(e.key), bytes: e.value, changed: d.changed(e.key)),
                                ],
                              ),
                      ),
                    ),
                    if (proto != null && proto != Proto.gattStandard) ...[
                      SectionTitle('Nhận ra kiểu cân'),
                      _presetCard(context, st, d, proto),
                    ],
                    SectionTitle('Cân cần kết nối'),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.link),
                        title: const Text('Bluetooth Weight Scale chuẩn'),
                        subtitle: Text(proto == Proto.gattStandard
                            ? 'Cân này báo có dịch vụ cân chuẩn, nên chọn cái này.'
                            : 'Dành cho cân không phát số ra ngoài mà bắt app kết nối vào.'),
                        trailing: const Icon(Icons.add),
                        onTap: () => _save(Proto.gattStandard, name: d.name),
                      ),
                    ),
                    SectionTitle('Dò byte cho cân lạ'),
                    Text(
                      'Đứng lên cân, đợi số trên màn hình cân đứng yên, nhập đúng số đó vào đây. Dòng tô xanh là vị trí byte khớp, chạm vào để lưu.',
                      style: t.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _known,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Số đang hiện trên cân', suffixText: unitLabel(st.unitLb)),
                    ),
                    const SizedBox(height: 8),
                    if (cands.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Chưa có byte nào ra giá trị hợp lý (2 đến 250 kg).'),
                      ),
                    for (final c in cands)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        color: c.match ? t.colorScheme.primaryContainer : null,
                        child: ListTile(
                          dense: true,
                          title: Text(fmtWU(c.value, st.unitLb, digits: 2),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${streamLabel(c.cfg.key)} · byte ${c.cfg.offset} · ${c.cfg.bigEndian ? 'BE' : 'LE'} · ÷${c.cfg.divisor.toStringAsFixed(0)}'
                              '${knownKg == null ? '' : ' · khớp ${score[c]}/${recent.length} gói'}'),
                          trailing: c.match
                              ? Icon(score[c]! >= 3 ? Icons.verified : Icons.check_circle)
                              : null,
                          onTap: () => _save(Proto.learned, config: c.cfg.toJson(), name: d.name),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _presetCard(BuildContext context, AppState st, SeenDevice d, Proto proto) {
    final tmp = SavedDevice(id: d.id, name: d.name, proto: proto);
    final r = parseAdv(tmp, d.packet);
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.verified),
        title: Text(proto.label),
        subtitle: Text(r == null
            ? 'Đang chờ số...'
            : 'Đang đọc được ${fmtWU(r.kg, st.unitLb, digits: 2)}${r.stable == true ? ' (đã chốt)' : ''}. Khớp với màn hình cân thì thêm.'),
        trailing: FilledButton(
          onPressed: () => _save(proto, name: d.name),
          child: const Text('Thêm'),
        ),
      ),
    );
  }
}

class _HexLine extends StatelessWidget {
  final String label;
  final List<int> bytes;
  final Set<int> changed;
  const _HexLine({required this.label, required this.bytes, required this.changed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          TextSpan(
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            children: [
              TextSpan(text: '$label  ', style: TextStyle(color: cs.onSurfaceVariant)),
              for (var i = 0; i < bytes.length; i++)
                TextSpan(
                  text: '${hex([bytes[i]])} ',
                  style: changed.contains(i)
                      ? TextStyle(
                          color: cs.error,
                          fontWeight: FontWeight.w700,
                          backgroundColor: cs.errorContainer)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
