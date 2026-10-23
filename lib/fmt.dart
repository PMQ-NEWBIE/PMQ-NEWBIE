import 'protocols.dart';

String two(int n) => n.toString().padLeft(2, '0');

double toUnit(double kg, bool lb) => lb ? kg / lbToKg : kg;
double fromUnit(double v, bool lb) => lb ? v * lbToKg : v;

String unitLabel(bool lb) => lb ? 'lb' : 'kg';

String fmtW(double kg, bool lb, {int digits = 2}) =>
    toUnit(kg, lb).toStringAsFixed(digits);

String fmtWU(double kg, bool lb, {int digits = 2}) =>
    '${fmtW(kg, lb, digits: digits)} ${unitLabel(lb)}';

String fmtDelta(double dKg, bool lb, {int digits = 2}) {
  final v = toUnit(dKg, lb);
  if (v.abs() < 0.005) return '±0 ${unitLabel(lb)}';
  final s = v > 0 ? '+' : '−';
  return '$s${v.abs().toStringAsFixed(digits)} ${unitLabel(lb)}';
}

String fmtDate(DateTime d) =>
    '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';

String fmtDay(DateTime d) => '${two(d.day)}/${two(d.month)}';

String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

const weekdaysVi = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

String timeAgo(DateTime d) {
  final s = DateTime.now().difference(d);
  if (s.inSeconds < 45) return 'vừa xong';
  if (s.inMinutes < 60) return '${s.inMinutes} phút trước';
  if (s.inHours < 24) return '${s.inHours} giờ trước';
  if (s.inDays < 30) return '${s.inDays} ngày trước';
  return fmtDate(d);
}

String hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
