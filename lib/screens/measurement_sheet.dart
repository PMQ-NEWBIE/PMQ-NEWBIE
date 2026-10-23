import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../fmt.dart';
import '../main.dart';
import '../metrics.dart';
import '../models.dart';
import '../widgets/common.dart';
import 'users_screen.dart';

String sourceLabel(String s) {
  switch (s) {
    case 'adv':
      return 'Nghe sóng cân';
    case 'gatt':
      return 'Kết nối cân (đồng bộ)';
    case 'bg':
      return 'Chạy nền khi app đóng';
    default:
      return 'Nhập tay';
  }
}

class ConfidenceChip extends StatelessWidget {
  final Confidence c;
  final bool dense;
  const ConfidenceChip(this.c, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, fg, bg) = switch (c) {
      Confidence.high => ('Tin cậy cao', Colors.green.shade700, Colors.green.withValues(alpha: 0.14)),
      Confidence.medium => ('Khá tin cậy', Colors.amber.shade800, Colors.amber.withValues(alpha: 0.18)),
      Confidence.low => ('Nên xem lại', cs.error, cs.errorContainer),
    };
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label,
          style: TextStyle(
              color: fg, fontSize: dense ? 11 : 12.5, fontWeight: FontWeight.w600)),
    );
  }
}

Future<void> showMeasurementDetail(BuildContext context, Measurement m) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _DetailSheet(m: m),
  );
}

class _DetailSheet extends StatefulWidget {
  final Measurement m;
  const _DetailSheet({required this.m});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  late final TextEditingController _note =
      TextEditingController(text: widget.m.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _saveNote(AppState st) async {
    if ((_note.text.trim()) == (widget.m.note ?? '')) return;
    await st.updateNote(widget.m, _note.text);
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final m = widget.m;
    final lb = st.unitLb;
    final u = st.userById(m.userId);
    final prev = st.previousOf(m);
    final hist = u == null ? <Measurement>[] : st.historyOf(u.id!);
    final avg7 = movingAverage(hist, m.at);
    final bmiV = m.bmi;
    final bmr = u == null ? null : st.bmrFor(u, m);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
        children: [
          // Đầu trang: số cân + thời gian + người
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(fmtWU(m.weightKg, lb, digits: 2),
                        style: t.textTheme.displaySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFeatures: const [FontFeature.tabularFigures()])),
                    const SizedBox(height: 2),
                    Text('${dayPart(m.at)} · ${fmtDate(m.at)}',
                        style: t.textTheme.bodyMedium
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              ConfidenceChip(m.confidence),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final x in st.users)
                ChoiceChip(
                  avatar: CircleAvatar(backgroundColor: Color(x.color), radius: 6),
                  label: Text(x.name),
                  selected: x.id == m.userId,
                  onSelected: (_) => st.assign(m, x.id!),
                ),
            ],
          ),

          const SectionTitle('So sánh'),
          _Grid(children: [
            _Fact(
              'Lần trước',
              prev == null ? 'Chưa có' : fmtDelta(m.weightKg - prev.weightKg, lb, digits: 2),
              sub: prev == null ? null : '${fmtWU(prev.weightKg, lb)} · ${timeAgoFrom(prev.at, m.at)}',
            ),
            _Fact(
              'Trung bình 7 ngày',
              avg7 == null ? 'Chưa có' : fmtWU(avg7, lb, digits: 2),
              sub: avg7 == null ? null : 'Lệch ${fmtDelta(m.weightKg - avg7, lb, digits: 2)}',
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(
              'Cân nặng lên xuống 1–2 kg trong ngày do nước và thức ăn. Nhìn số trung bình 7 ngày mới thấy xu hướng thật.',
              style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),

          const SectionTitle('Chỉ số cơ thể'),
          _Grid(children: [
            _Fact(
              'BMI',
              bmiV == null ? 'Thiếu chiều cao' : bmiV.toStringAsFixed(1),
              sub: bmiV == null ? null : bmiBandAsia(bmiV).label,
              onTap: bmiV == null && u != null ? () => showUserEditor(context, u) : null,
            ),
            _Fact(
              'Năng lượng nghỉ',
              bmr == null ? 'Thiếu hồ sơ' : '${bmr.round()} kcal/ngày',
              sub: bmr == null ? 'Cần giới tính, năm sinh, chiều cao' : bmrSource,
              onTap: bmr == null && u != null ? () => showUserEditor(context, u) : null,
            ),
            _Fact(
              'Trở kháng',
              m.impedance == null ? 'Không có' : '${m.impedance} Ω',
              sub: m.impedance == null ? 'Cân không gửi hoặc chưa giải mã' : 'Dùng để tính % mỡ',
            ),
          ]),
          if (bmiV != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 2),
              child: Text('BMI phân loại theo $bmiSource: bình thường 18,5–22,9; thừa cân từ 23.',
                  style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ),

          const SectionTitle('Phiên cân'),
          Card(
            child: Column(children: [
              _Row('Nguồn', sourceLabel(m.source)),
              if (m.deviceName != null) _Row('Thiết bị', m.deviceName!),
              if (m.method != null) _Row('Cách chốt số', m.method!.label),
              if (m.samples != null) _Row('Số gói nhận', '${m.samples}'),
              if (m.durationMs != null)
                _Row('Thời gian đứng', '${(m.durationMs! / 1000).toStringAsFixed(1)} giây'),
              if (m.minKg != null && m.maxKg != null)
                _Row('Dao động',
                    '${fmtW(m.minKg!, lb, digits: 2)} → ${fmtW(m.maxKg!, lb, digits: 2)} ${unitLabel(lb)}'),
              if (m.heightCm != null) _Row('Chiều cao lúc cân', '${m.heightCm!.toStringAsFixed(0)} cm'),
            ]),
          ),

          const SectionTitle('Ghi chú'),
          TextField(
            controller: _note,
            maxLines: 2,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: 'Ví dụ: sáng chưa ăn, sau khi tập'),
            onSubmitted: (_) => _saveNote(st),
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
              _saveNote(st);
            },
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final q in const ['Sáng chưa ăn', 'Sau ăn', 'Sau tập', 'Mặc đồ dày'])
              ActionChip(
                label: Text(q),
                onPressed: () {
                  _note.text = _note.text.trim().isEmpty ? q : '${_note.text.trim()}, $q';
                  _saveNote(st);
                },
              ),
          ]),

          if (m.raw != null) ...[
            SectionTitle('Byte thô',
                trailing: TextButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Chép'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: m.raw!));
                    if (context.mounted) toast(context, 'Đã chép byte thô');
                  },
                )),
            SelectableText(m.raw!,
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: 13, color: cs.onSurfaceVariant)),
          ],

          const SizedBox(height: 24),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cs.error),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Xoá lần cân này'),
            onPressed: () async {
              final ok = await confirmDialog(context,
                  title: 'Xoá lần cân này?',
                  message: '${fmtWU(m.weightKg, lb, digits: 2)} lúc ${fmtDate(m.at)}.');
              if (!ok) return;
              await st.deleteMeasurement(m);
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

String timeAgoFrom(DateTime earlier, DateTime later) {
  final d = later.difference(earlier);
  if (d.inMinutes < 60) return '${d.inMinutes} phút trước đó';
  if (d.inHours < 24) return '${d.inHours} giờ trước đó';
  return '${d.inDays} ngày trước đó';
}

class _Grid extends StatelessWidget {
  final List<Widget> children;
  const _Grid({required this.children});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final cols = box.maxWidth > 520 ? 3 : 2;
        final w = (box.maxWidth - 10 * (cols - 1)) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      });
}

class _Fact extends StatelessWidget {
  final String label, value;
  final String? sub;
  final VoidCallback? onTap;
  const _Fact(this.label, this.value, {this.sub, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: t.textTheme.labelMedium
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(value,
                  style: t.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: onTap != null ? t.colorScheme.primary : null,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              if (sub != null)
                Text(sub!,
                    style: t.textTheme.bodySmall
                        ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String k, v;
  const _Row(this.k, this.v);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              flex: 4,
              child: Text(k,
                  style: t.textTheme.bodyMedium
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant))),
          Expanded(
              flex: 6,
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
