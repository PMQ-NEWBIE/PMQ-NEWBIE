import 'package:flutter/material.dart';

import '../fmt.dart';
import '../app_state.dart';
import '../main.dart';
import '../native.dart';
import '../widgets/common.dart';
import 'history_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          MaxWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle('Hiển thị'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Đơn vị cân nặng'),
                        const SizedBox(height: 8),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('kg')),
                            ButtonSegment(value: true, label: Text('lb')),
                          ],
                          selected: {st.unitLb},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => st.setUnitLb(s.first),
                        ),
                        const SizedBox(height: 16),
                        const Text('Giao diện'),
                        const SizedBox(height: 8),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.brightness_auto),
                                label: Text('Theo máy')),
                            ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode),
                                label: Text('Sáng')),
                            ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode),
                                label: Text('Tối')),
                          ],
                          selected: {st.themeMode},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => st.setTheme(s.first),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Nhiều người dùng'),
                Card(
                  child: SwitchListTile(
                    title: const Text('Tự nhận diện người cân'),
                    subtitle: const Text(
                        'Đoán theo số cân gần nhất của từng người. Tắt đi thì số luôn ghi cho người đang chọn.'),
                    value: st.autoAssign,
                    onChanged: st.setAutoAssign,
                  ),
                ),
                const SectionTitle('Chạy nền'),
                const _BackgroundCard(),
                const SectionTitle('Nhắc cân định kỳ'),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Bật nhắc nhở'),
                        subtitle: Text(st.reminderOn
                            ? 'Nhắc lúc ${two(st.reminderHour)}:${two(st.reminderMinute)}'
                            : 'Đang tắt'),
                        value: st.reminderOn,
                        onChanged: (v) => st.setReminder(on: v),
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 250),
                        crossFadeState: st.reminderOn
                            ? CrossFadeState.showSecond
                            : CrossFadeState.showFirst,
                        firstChild: const SizedBox(width: double.infinity),
                        secondChild: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.schedule),
                                label: Text(
                                    'Giờ nhắc ${two(st.reminderHour)}:${two(st.reminderMinute)}'),
                                onPressed: () async {
                                  final tm = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(
                                        hour: st.reminderHour, minute: st.reminderMinute),
                                  );
                                  if (tm != null) {
                                    await st.setReminder(hour: tm.hour, minute: tm.minute);
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (var i = 0; i < 7; i++)
                                    FilterChip(
                                      label: Text(weekdaysVi[i]),
                                      selected: (st.reminderDays & (1 << i)) != 0,
                                      onSelected: (v) => st.setReminder(
                                          days: v
                                              ? st.reminderDays | (1 << i)
                                              : st.reminderDays & ~(1 << i)),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Mẹo: cân cùng giờ mỗi ngày, tốt nhất là buổi sáng sau khi đi vệ sinh, số mới so sánh được với nhau.',
                                style: t.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Dữ liệu'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.file_download_outlined),
                        title: const Text('Xuất toàn bộ lịch sử (CSV)'),
                        subtitle: Text('${st.measurements.length} lần cân, mở được bằng Excel'),
                        onTap: () => exportCsv(context, st),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.delete_forever_outlined, color: t.colorScheme.error),
                        title: Text('Xoá toàn bộ lịch sử',
                            style: TextStyle(color: t.colorScheme.error)),
                        subtitle: const Text('Giữ lại người dùng và cân đã lưu'),
                        onTap: () async {
                          final ok = await confirmDialog(context,
                              title: 'Xoá toàn bộ lịch sử?',
                              message:
                                  'Xoá ${st.measurements.length} lần cân của mọi người. Không khôi phục được.');
                          if (ok) {
                            await st.deleteAllHistory();
                            if (context.mounted) toast(context, 'Đã xoá toàn bộ lịch sử');
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SectionTitle('Cách app nhận số'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Cân kiểu phát quảng bá (Xiaomi, đa số cân rẻ): app chỉ nghe sóng, không cần kết nối, số chốt là lưu.\n\n'
                      'Cân kiểu kết nối chuẩn: khi cân thức, app tự kết nối và nhận cả các lần cân cân còn giữ trong bộ nhớ (đồng bộ). Bản ghi trùng sẽ tự bỏ qua.\n\n'
                      'App chỉ nghe khi đang mở. Tất cả dữ liệu nằm trong máy, không gửi đi đâu.',
                      style: t.textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundCard extends StatefulWidget {
  const _BackgroundCard();

  @override
  State<_BackgroundCard> createState() => _BackgroundCardState();
}

class _BackgroundCardState extends State<_BackgroundCard> with WidgetsBindingObserver {
  BgStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Quay lại từ màn cài đặt pin của Android thì đọc lại trạng thái.
    if (s == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final s = await NativeBridge.backgroundStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _toggle(AppState st, bool v) async {
    await st.setBackground(v);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final s = _status;
    final hasAdvScale = st.devices.any((d) => !d.proto.needsConnection);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            title: const Text('Tự ghi khi app đang đóng'),
            subtitle: Text(!hasAdvScale
                ? 'Cần thêm một cân kiểu nghe sóng trước (cân kết nối chuẩn tự giữ lịch sử, mở app là đồng bộ).'
                : 'Bật Bluetooth, bước lên cân là số tự được lưu, có thông báo kết quả.'),
            value: st.backgroundOn,
            onChanged: hasAdvScale || st.backgroundOn ? (v) => _toggle(st, v) : null,
          ),
          if (st.backgroundOn) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                s?.running == true ? Icons.check_circle : Icons.error_outline,
                color: s?.running == true ? Colors.green : cs.error,
              ),
              title: Text(s == null
                  ? 'Đang kiểm tra...'
                  : (s.running ? 'Đang chạy nền' : 'Chưa chạy được')),
              subtitle: s?.error == null ? null : Text(s!.error!),
              trailing: IconButton(
                tooltip: 'Kiểm tra lại',
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ),
            if (s != null && !s.batteryUnrestricted)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: ErrorCard(
                  warning: true,
                  title: 'Android có thể tắt app để tiết kiệm pin',
                  message:
                      'Cho phép Cân Lỏ chạy không giới hạn pin để không bị lỡ lần cân. Máy Xiaomi, Oppo, Samsung còn có mục "Tự khởi động" hoặc "Không tối ưu" riêng, nên bật luôn.',
                  actionLabel: 'Mở cài đặt pin',
                  onAction: NativeBridge.requestBatteryUnrestricted,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                'Chạy nền dùng chế độ quét tiết kiệm pin, chỉ lọc đúng địa chỉ cân đã lưu. Khi có người đứng lên cân mới chuyển sang quét nhanh để bắt đủ số.',
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
