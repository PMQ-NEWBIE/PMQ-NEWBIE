import 'package:flutter/material.dart';

import '../app_state.dart';
import '../fmt.dart';
import '../main.dart';
import '../metrics.dart';
import '../models.dart';
import '../native.dart';
import '../widgets/common.dart';
import '../widgets/weight_chart.dart';
import 'measurement_sheet.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _range = 30; // ngày, 0 = tất cả
  bool _compare = false;
  final List<Measurement> _picked = [];

  void _toggle(Measurement m) {
    setState(() {
      if (_picked.contains(m)) {
        _picked.remove(m);
      } else {
        if (_picked.length == 2) _picked.removeAt(0);
        _picked.add(m);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final u = st.activeUser;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lịch sử'),
        actions: [
          IconButton(
            tooltip: _compare ? 'Tắt so sánh' : 'So sánh 2 lần cân',
            isSelected: _compare,
            icon: const Icon(Icons.compare_arrows),
            onPressed: () => setState(() {
              _compare = !_compare;
              _picked.clear();
            }),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, st, v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'export_user', child: Text('Xuất CSV người đang chọn')),
              const PopupMenuItem(value: 'export_all', child: Text('Xuất CSV tất cả')),
              const PopupMenuDivider(),
              PopupMenuItem(
                  value: 'clear_user',
                  child: Text('Xoá lịch sử của ${u?.name ?? ''}')),
            ],
          ),
        ],
      ),
      body: st.loading
          ? ListView(padding: const EdgeInsets.all(16), children: const [
              Skeleton(height: 40, radius: 20),
              SizedBox(height: 12),
              Skeleton(height: 240, radius: 18),
              SizedBox(height: 12),
              Skeleton(height: 56),
              SizedBox(height: 8),
              Skeleton(height: 56),
              SizedBox(height: 8),
              Skeleton(height: 56),
            ])
          : _body(context, st, u),
    );
  }

  Widget _body(BuildContext context, AppState st, UserProfile? u) {
    if (u == null) return const SizedBox.shrink();
    final all = st.historyOf(u.id!);
    if (all.isEmpty) {
      return Column(children: [
        _userChips(st),
        const Expanded(
          child: EmptyState(
            icon: Icons.insights_outlined,
            title: 'Chưa có dữ liệu',
            message:
                'Mỗi lần cân xong, số sẽ tự vào đây kèm biểu đồ và mức thay đổi.',
          ),
        ),
      ]);
    }
    final from = _range == 0
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.now().subtract(Duration(days: _range));
    final data = all.where((m) => m.at.isAfter(from)).toList();
    final list = data.reversed.toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        MaxWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _userChips(st),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7N')),
                  ButtonSegment(value: 30, label: Text('30N')),
                  ButtonSegment(value: 90, label: Text('90N')),
                  ButtonSegment(value: 0, label: Text('Tất cả')),
                ],
                selected: {_range},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
                  child: data.isEmpty
                      ? const SizedBox(
                          height: 160,
                          child: Center(child: Text('Không có lần cân nào trong khoảng này')))
                      : WeightChart(
                          data: data,
                          average: [for (final m in data) movingAverage(all, m.at)],
                          lb: st.unitLb,
                          goalKg: u.goalKg,
                          color: Color(u.color),
                        ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: _compare ? _compareCard(context, st) : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < list.length; i++) ...[
                if (i == 0 || list[i - 1].at.month != list[i].at.month ||
                    list[i - 1].at.year != list[i].at.year)
                  SectionTitle('Tháng ${list[i].at.month}/${list[i].at.year}'),
                _row(context, st, list[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _userChips(AppState st) {
    if (st.users.length < 2) return const SizedBox(height: 4);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        for (final x in st.users)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              avatar: CircleAvatar(backgroundColor: Color(x.color), radius: 6),
              label: Text(x.name),
              selected: x.id == st.activeUserId,
              onSelected: (_) {
                _picked.clear();
                st.setActiveUser(x.id!);
              },
            ),
          ),
      ]),
    );
  }

  Widget _compareCard(BuildContext context, AppState st) {
    final cs = Theme.of(context).colorScheme;
    Widget inner;
    if (_picked.length < 2) {
      inner = Text(
          _picked.isEmpty
              ? 'Chạm 2 lần cân bất kỳ bên dưới để so sánh'
              : 'Chọn thêm 1 lần cân nữa',
          style: TextStyle(color: cs.onSecondaryContainer));
    } else {
      final a = _picked[0].at.isBefore(_picked[1].at) ? _picked[0] : _picked[1];
      final b = identical(a, _picked[0]) ? _picked[1] : _picked[0];
      final diff = b.weightKg - a.weightKg;
      final days = b.at.difference(a.at).inHours / 24;
      final perWeek = days >= 1 ? diff / days * 7 : null;
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _cmpCol(context, st, 'Trước', a)),
            Icon(Icons.arrow_forward, color: cs.onSecondaryContainer),
            Expanded(child: _cmpCol(context, st, 'Sau', b)),
          ]),
          const Divider(),
          Text(
            'Chênh ${fmtDelta(diff, st.unitLb, digits: 2)} sau '
            '${days < 1 ? '${(days * 24).round()} giờ' : '${days.toStringAsFixed(days < 10 ? 1 : 0)} ngày'}'
            '${perWeek == null ? '' : ' · trung bình ${fmtDelta(perWeek, st.unitLb, digits: 2)}/tuần'}',
            style: TextStyle(
                color: cs.onSecondaryContainer, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: cs.secondaryContainer,
        child: Padding(padding: const EdgeInsets.all(14), child: inner),
      ),
    );
  }

  Widget _cmpCol(BuildContext context, AppState st, String label, Measurement m) {
    final cs = Theme.of(context).colorScheme;
    return Column(children: [
      Text(label, style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
      Text(fmtWU(m.weightKg, st.unitLb, digits: 2),
          style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer)),
      Text(fmtDate(m.at), style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
    ]);
  }

  Widget _row(BuildContext context, AppState st, Measurement m) {
    final cs = Theme.of(context).colorScheme;
    final prev = st.previousOf(m);
    final delta = prev == null ? null : m.weightKg - prev.weightKg;
    final picked = _picked.contains(m);
    final icon = switch (m.source) {
      'manual' => Icons.edit_outlined,
      'gatt' => Icons.sync,
      'bg' => Icons.bedtime_outlined,
      _ => Icons.bluetooth,
    };
    final u = st.userById(m.userId);
    final tile = ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: _compare
          ? Checkbox(value: picked, onChanged: (_) => _toggle(m))
          : CircleAvatar(
              radius: 18,
              backgroundColor: cs.surfaceContainerHighest,
              child: Icon(icon, size: 18, color: cs.onSurfaceVariant)),
      title: Text(fmtWU(m.weightKg, st.unitLb, digits: 2),
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()])),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${dayPart(m.at)} · ${fmtDate(m.at)}'),
          if (m.note != null)
            Text(m.note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
          if (m.confidence != Confidence.high)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ConfidenceChip(m.confidence, dense: true),
            ),
        ],
      ),
      trailing: delta == null
          ? null
          : Text(fmtDelta(delta, st.unitLb),
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: deltaColor(context, delta, goal: u?.goalKg, current: m.weightKg))),
      onTap: _compare ? () => _toggle(m) : () => showMeasurementDetail(context, m),
    );
    if (_compare) return tile;
    return Dismissible(
      key: ObjectKey(m),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
            color: cs.errorContainer, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) {
        st.deleteMeasurement(m);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('Đã xoá ${fmtWU(m.weightKg, st.unitLb)}'),
            action: SnackBarAction(
                label: 'Hoàn tác', onPressed: () => st.restoreMeasurement(m)),
          ));
      },
      child: tile,
    );
  }

  Future<void> _menu(BuildContext context, AppState st, String v) async {
    final u = st.activeUser;
    switch (v) {
      case 'export_user':
      case 'export_all':
        await exportCsv(context, st, userId: v == 'export_user' ? u?.id : null);
        break;
      case 'clear_user':
        if (u == null) return;
        final ok = await confirmDialog(context,
            title: 'Xoá lịch sử của ${u.name}?',
            message: 'Mọi lần cân của người này bị xoá. Nên xuất CSV trước nếu muốn giữ.');
        if (ok) {
          await st.deleteHistoryOf(u.id!);
          if (context.mounted) toast(context, 'Đã xoá lịch sử của ${u.name}');
        }
        break;
    }
  }
}

Future<void> exportCsv(BuildContext context, AppState st, {int? userId}) async {
  final count = st.measurements
      .where((m) => userId == null || m.userId == userId)
      .length;
  if (count == 0) {
    toast(context, 'Chưa có gì để xuất');
    return;
  }
  final now = DateTime.now();
  final who = userId == null ? 'tat-ca' : (st.userById(userId)?.name ?? 'user');
  final name =
      'can-lo-$who-${now.year}${two(now.month)}${two(now.day)}.csv'.replaceAll(' ', '-');
  try {
    final ok = await NativeBridge.saveTextFile(name, st.buildCsv(userId: userId));
    if (context.mounted && ok) toast(context, 'Đã lưu $count dòng vào $name');
  } catch (e) {
    if (context.mounted) toast(context, 'Không lưu được file: $e');
  }
}
