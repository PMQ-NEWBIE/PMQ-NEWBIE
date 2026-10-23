import 'package:flutter/material.dart';

import '../fmt.dart';
import '../main.dart';
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
