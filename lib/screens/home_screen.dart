import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../app_state.dart';
import '../ble_service.dart';
import '../fmt.dart';
import '../main.dart';
import '../models.dart';
import '../widgets/common.dart';
import '../widgets/weight_chart.dart';
import 'users_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  Measurement? _shown;

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    if (st.justSaved != null && !identical(st.justSaved, _shown)) {
      final m = st.justSaved!;
      _shown = m;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pop.forward(from: 0);
        final u = st.userById(m.userId);
        toast(
            context,
            u == null
                ? 'Đã ghi ${fmtWU(m.weightKg, st.unitLb)}, chọn người cân bên dưới'
                : 'Đã lưu ${fmtWU(m.weightKg, st.unitLb)} cho ${u.name}');
      });
    }

    return Scaffold(
      floatingActionButton: st.loading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showManualEntry(context),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Nhập tay'),
            ),
      body: SafeArea(
        child: st.loading
            ? const _HomeSkeleton()
            : RefreshIndicator(
                onRefresh: () => st.ble.startScan(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                  children: [
                    MaxWidth(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(st: st),
                          const SizedBox(height: 12),
                          if (st.fatalError != null)
                            ErrorCard(
                                title: 'Lỗi dữ liệu', message: st.fatalError!),
                          _ConnectionCard(st: st),
                          const SizedBox(height: 12),
                          _HeroCard(st: st, pop: _pop),
                          for (final m in st.pending) _PendingCard(st: st, m: m),
                          const SizedBox(height: 12),
                          _Stats(st: st),
                          const SizedBox(height: 12),
                          _GoalCard(st: st),
                          const SizedBox(height: 12),
                          _MiniChart(st: st),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AppState st;
  const _Header({required this.st});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final u = st.activeUser;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cân Lỏ',
            style: t.textTheme.labelLarge?.copyWith(
                color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
        Text('Chào ${u?.name ?? ''}', style: t.textTheme.headlineSmall),
        if (st.users.length > 1) ...[
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final x in st.users)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: CircleAvatar(backgroundColor: Color(x.color), radius: 6),
                      label: Text(x.name),
                      selected: x.id == st.activeUserId,
                      onSelected: (_) => st.setActiveUser(x.id!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final AppState st;
  const _ConnectionCard({required this.st});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: st.ble,
      builder: (context, _) {
        final ble = st.ble;
        final shell = ShellNav.of(context);
        if (!ble.supported) {
          return const ErrorCard(
              title: 'Máy không hỗ trợ Bluetooth LE',
              message: 'Vẫn dùng được bằng cách nhập tay số cân.');
        }
        if (st.devices.isEmpty) {
          return ErrorCard(
            warning: true,
            title: 'Chưa có cân nào',
            message:
                'Vào tab Thiết bị, bước lên cân để nó phát sóng rồi chọn cân trong danh sách.',
            actionLabel: 'Thêm cân',
            onAction: () => shell?.go(2),
          );
        }
        if (ble.adapter == BluetoothAdapterState.off) {
          return ErrorCard(
            title: 'Bluetooth đang tắt',
            message: 'Bật Bluetooth để app nghe được cân.',
            actionLabel: 'Bật Bluetooth',
            onAction: ble.turnOn,
          );
        }
        if (ble.scanError != null) {
          return ErrorCard(
            title: 'Không quét được',
            message: ble.scanError!,
            actionLabel: 'Thử lại',
            onAction: ble.startScan,
          );
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                for (final d in st.devices)
                  DeviceStatusRow(device: d, link: ble.links[d.id], scanning: ble.scanning),
                if (st.syncedThisSession > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                        'Đã đồng bộ ${st.syncedThisSession} bản ghi từ cân',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Lấy ShellState để chuyển tab.
class ShellNav {
  static ShellState? of(BuildContext context) => ShellState.of(context);
}

class DeviceStatusRow extends StatelessWidget {
  final SavedDevice device;
  final DeviceLink? link;
  final bool scanning;
  const DeviceStatusRow(
      {super.key, required this.device, required this.link, required this.scanning});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = link?.state ?? LinkState.idle;
    late Color color;
    late String text;
    var active = false;
    var busy = false;
    switch (s) {
      case LinkState.connected:
        color = Colors.green;
        text = 'Đã kết nối';
        break;
      case LinkState.listening:
        color = Colors.green;
        text = device.proto.needsConnection ? 'Đang chờ cân' : 'Đang nghe cân';
        active = true;
        break;
      case LinkState.connecting:
        color = Colors.amber.shade700;
        text = 'Đang kết nối...';
        active = true;
        busy = true;
        break;
      case LinkState.syncing:
        color = cs.primary;
        text = 'Đang đồng bộ...';
        active = true;
        busy = true;
        break;
      case LinkState.lost:
        color = cs.outline;
        text = 'Cân đang ngủ (bước lên để đánh thức)';
        break;
      case LinkState.error:
        color = cs.error;
        text = link?.error ?? 'Lỗi kết nối';
        break;
      case LinkState.idle:
        color = cs.outline;
        text = scanning ? 'Chưa thấy cân, bước lên cân thử' : 'Chưa quét';
        break;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              PulseDot(color: color, active: active),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(text,
                          key: ValueKey(text),
                          style: TextStyle(
                              fontSize: 12.5,
                              color: s == LinkState.error ? cs.error : cs.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 30),
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final AppState st;
  final AnimationController pop;
  const _HeroCard({required this.st, required this.pop});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final u = st.activeUser;
    final live = st.live;
    final isLive = live != null &&
        DateTime.now().difference(live.at) < const Duration(seconds: 6);
    final latest = u == null ? null : st.latestFor(u.id!);

    Widget content;
    if (isLive) {
      final l = live!;
      content = Column(
        key: const ValueKey('live'),
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            PulseDot(color: l.settled ? Colors.green : cs.primary, active: !l.settled),
            Text(l.settled ? 'Đã chốt số' : 'Đang đo, đứng yên nhé...',
                style: t.textTheme.labelLarge),
          ]),
          const SizedBox(height: 6),
          _BigNumber(kg: l.kg, lb: st.unitLb, color: cs.onSurface),
        ],
      );
    } else if (latest == null) {
      content = const SizedBox(
        key: ValueKey('empty'),
        child: EmptyState(
          icon: Icons.monitor_weight_outlined,
          title: 'Chưa có lần cân nào',
          message: 'Bước lên cân đã thêm, hoặc bấm Nhập tay để ghi số.',
        ),
      );
    } else {
      final prev = st.previousOf(latest);
      content = Column(
        key: const ValueKey('latest'),
        children: [
          Text('Lần cân gần nhất · ${timeAgo(latest.at)}',
              style: t.textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          _BigNumber(kg: latest.weightKg, lb: st.unitLb, color: cs.onSurface),
          if (prev != null) ...[
            const SizedBox(height: 4),
            _DeltaChip(delta: latest.weightKg - prev.weightKg, lb: st.unitLb, goal: u?.goalKg, current: latest.weightKg),
          ],
        ],
      );
    }

    return AnimatedBuilder(
      animation: pop,
      builder: (context, child) {
        final v = pop.value;
        final scale = v == 0 ? 1.0 : 0.94 + 0.06 * Curves.elasticOut.transform(v);
        final glow = (1 - v) * (v > 0 ? 1 : 0);
        return Transform.scale(
          scale: scale,
          child: Card(
            color: Color.lerp(cs.surfaceContainerLow, cs.primaryContainer, glow * 0.8),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: content,
        ),
      ),
    );
  }
}

class _BigNumber extends StatelessWidget {
  final double kg;
  final bool lb;
  final Color color;
  const _BigNumber({required this.kg, required this.lb, required this.color});

  @override
  Widget build(BuildContext context) {
    final target = toUnit(kg, lb);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(v.toStringAsFixed(1),
              style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  color: color,
                  letterSpacing: -1.5,
                  fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text(unitLabel(lb),
              style: TextStyle(
                  fontSize: 22, color: color.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

class _DeltaChip extends StatelessWidget {
  final double delta;
  final bool lb;
  final double? goal;
  final double current;
  const _DeltaChip(
      {required this.delta, required this.lb, required this.goal, required this.current});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    bool? good;
    if (goal != null && delta.abs() >= 0.05) {
      good = (goal! < current) ? delta < 0 : delta > 0;
    }
    final color = good == null
        ? cs.onSurfaceVariant
        : (good ? Colors.green.shade600 : cs.error);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
            delta.abs() < 0.05
                ? Icons.remove
                : (delta > 0 ? Icons.arrow_upward : Icons.arrow_downward),
            size: 16,
            color: color),
        const SizedBox(width: 2),
        Text('${fmtDelta(delta, lb)} so với lần trước',
            style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PendingCard extends StatelessWidget {
  final AppState st;
  final Measurement m;
  const _PendingCard({required this.st, required this.m});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: cs.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ai vừa cân ${fmtWU(m.weightKg, st.unitLb)}?',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: cs.onSecondaryContainer)),
              Text('${fmtDate(m.at)} · không đoán chắc được người nào',
                  style: TextStyle(fontSize: 12, color: cs.onSecondaryContainer)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final u in st.users)
                    ActionChip(
                      avatar: CircleAvatar(backgroundColor: Color(u.color), radius: 6),
                      label: Text(u.name),
                      onPressed: () => st.assign(m, u.id!),
                    ),
                  TextButton(
                    onPressed: () => st.deleteMeasurement(m),
                    child: const Text('Bỏ số này'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final AppState st;
  const _Stats({required this.st});

  @override
  Widget build(BuildContext context) {
    final u = st.activeUser;
    if (u == null) return const SizedBox.shrink();
    final hist = st.historyOf(u.id!);
    if (hist.isEmpty) return const SizedBox.shrink();
    final trend = st.trendPerWeek(u.id!);
    final bmi = st.bmi(u);
    final items = <Widget>[
      _StatTile(
        label: 'Xu hướng 30 ngày',
        value: trend == null ? 'Chưa đủ dữ liệu' : '${fmtDelta(trend, st.unitLb, digits: 2)}/tuần',
        icon: trend == null
            ? Icons.timeline
            : (trend > 0.05
                ? Icons.trending_up
                : (trend < -0.05 ? Icons.trending_down : Icons.trending_flat)),
      ),
      _StatTile(label: 'Số lần cân', value: '${hist.length}', icon: Icons.format_list_numbered),
      _StatTile(
        label: 'Thấp nhất / cao nhất',
        value:
            '${fmtW(hist.map((e) => e.weightKg).reduce((a, b) => a < b ? a : b), st.unitLb)} / ${fmtW(hist.map((e) => e.weightKg).reduce((a, b) => a > b ? a : b), st.unitLb)}',
        icon: Icons.unfold_more,
      ),
      _StatTile(
        label: 'BMI',
        value: bmi == null ? 'Nhập chiều cao' : bmi.toStringAsFixed(1),
        icon: Icons.accessibility_new,
        onTap: bmi == null ? () => showUserEditor(context, u) : null,
      ),
    ];
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth > 560 ? 4 : 2;
      final w = (box.maxWidth - 10 * (cols - 1)) / cols;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [for (final i in items) SizedBox(width: w, child: i)],
      );
    });
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final VoidCallback? onTap;
  const _StatTile(
      {required this.label, required this.value, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: t.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value,
                  style: t.textTheme.titleMedium
                      ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              Text(label,
                  style: t.textTheme.bodySmall
                      ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final AppState st;
  const _GoalCard({required this.st});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final u = st.activeUser;
    if (u == null) return const SizedBox.shrink();
    if (u.goalKg == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.flag_outlined),
          title: const Text('Chưa đặt mục tiêu'),
          subtitle: const Text('Đặt cân nặng mục tiêu để theo dõi tiến độ'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showUserEditor(context, u),
        ),
      );
    }
    final p = st.goalProgress(u) ?? 0;
    final cur = st.latestFor(u.id!)?.weightKg;
    final left = cur == null ? null : u.goalKg! - cur;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showUserEditor(context, u),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.flag, color: t.colorScheme.tertiary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Mục tiêu ${fmtWU(u.goalKg!, st.unitLb)}',
                        style: t.textTheme.titleSmall)),
                Text('${(p * 100).round()}%',
                    style: t.textTheme.titleSmall
                        ?.copyWith(color: t.colorScheme.tertiary)),
              ]),
              const SizedBox(height: 10),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: v,
                    minHeight: 10,
                    color: t.colorScheme.tertiary,
                    backgroundColor: t.colorScheme.tertiaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                left == null
                    ? 'Cân lần đầu để bắt đầu tính tiến độ'
                    : (left.abs() < 0.1
                        ? 'Đạt mục tiêu rồi, ghê đó'
                        : 'Còn ${fmtW(left.abs(), st.unitLb)} ${unitLabel(st.unitLb)} nữa${left < 0 ? ' cần giảm' : ' cần tăng'}'),
                style: t.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniChart extends StatelessWidget {
  final AppState st;
  const _MiniChart({required this.st});

  @override
  Widget build(BuildContext context) {
    final u = st.activeUser;
    if (u == null) return const SizedBox.shrink();
    final from = DateTime.now().subtract(const Duration(days: 30));
    final data = st.historyOf(u.id!).where((m) => m.at.isAfter(from)).toList();
    if (data.length < 2) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 6),
              child: Text('30 ngày qua · chạm để xem từng lần',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            WeightChart(
                data: data,
                lb: st.unitLb,
                goalKg: u.goalKg,
                color: Color(u.color),
                height: 180),
          ],
        ),
      ),
    );
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Skeleton(width: 80, height: 14),
        SizedBox(height: 8),
        Skeleton(width: 180, height: 28),
        SizedBox(height: 16),
        Skeleton(height: 64, radius: 18),
        SizedBox(height: 12),
        Skeleton(height: 170, radius: 18),
        SizedBox(height: 12),
        Row(children: [
          Expanded(child: Skeleton(height: 90, radius: 18)),
          SizedBox(width: 10),
          Expanded(child: Skeleton(height: 90, radius: 18)),
        ]),
        SizedBox(height: 12),
        Skeleton(height: 200, radius: 18),
      ],
    );
  }
}

Future<void> showManualEntry(BuildContext context) async {
  final st = AppScope.read(context);
  final u = st.activeUser;
  if (u == null) return;
  final ctrl = TextEditingController();
  var at = DateTime.now();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => AlertDialog(
        title: Text('Nhập tay cho ${u.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: 'Cân nặng', suffixText: unitLabel(st.unitLb)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(fmtDate(at)),
              onPressed: () async {
                final d = await showDatePicker(
                    context: c,
                    initialDate: at,
                    firstDate: DateTime(2015),
                    lastDate: DateTime.now());
                if (d == null || !c.mounted) return;
                final tm = await showTimePicker(
                    context: c, initialTime: TimeOfDay.fromDateTime(at));
                setS(() => at = DateTime(d.year, d.month, d.day,
                    tm?.hour ?? at.hour, tm?.minute ?? at.minute));
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lưu')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
  if (!context.mounted) return;
  if (v == null || v <= 0 || fromUnit(v, st.unitLb) > 400) {
    toast(context, 'Số cân không hợp lệ, nhập lại kiểu 68.4');
    return;
  }
  await st.addManual(fromUnit(v, st.unitLb), at, u.id!);
}
