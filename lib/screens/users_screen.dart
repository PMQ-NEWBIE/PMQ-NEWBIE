import 'package:flutter/material.dart';

import '../app_state.dart';
import '../fmt.dart';
import '../main.dart';
import '../models.dart';
import '../widgets/common.dart';

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppScope.of(context);
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Người dùng')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showUserEditor(context, null),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Thêm người'),
      ),
      body: st.loading
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: const [
                Skeleton(height: 72, radius: 18),
                SizedBox(height: 10),
                Skeleton(height: 72, radius: 18),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                MaxWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Cả nhà dùng chung một cân được. App tự đoán ai vừa cân dựa trên số lần trước; đoán không chắc thì hỏi lại ở màn Tổng quan.',
                        style: t.textTheme.bodySmall
                            ?.copyWith(color: t.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      for (final u in st.users) ...[
                        _UserTile(st: st, u: u),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final AppState st;
  final UserProfile u;
  const _UserTile({required this.st, required this.u});

  @override
  Widget build(BuildContext context) {
    final last = st.latestFor(u.id!);
    final active = u.id == st.activeUserId;
    final cs = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: active ? BorderSide(color: cs.primary, width: 2) : BorderSide.none,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: Color(u.color),
          foregroundColor: Colors.white,
          child: Text(u.name.isEmpty ? '?' : u.name.characters.first.toUpperCase()),
        ),
        title: Text(u.name),
        subtitle: Text([
          last == null ? 'Chưa cân lần nào' : fmtWU(last.weightKg, st.unitLb),
          if (u.goalKg != null) 'mục tiêu ${fmtWU(u.goalKg!, st.unitLb)}',
        ].join(' · ')),
        trailing: active
            ? Chip(label: const Text('Đang chọn'), backgroundColor: cs.primaryContainer)
            : TextButton(
                onPressed: () => st.setActiveUser(u.id!),
                child: const Text('Chọn')),
        onTap: () => showUserEditor(context, u),
      ),
    );
  }
}

Future<void> showUserEditor(BuildContext context, UserProfile? user) async {
  final st = AppScope.read(context);
  final lb = st.unitLb;
  final name = TextEditingController(text: user?.name ?? '');
  final height = TextEditingController(
      text: user?.heightCm == null ? '' : user!.heightCm!.toStringAsFixed(0));
  final goal = TextEditingController(
      text: user?.goalKg == null ? '' : fmtW(user!.goalKg!, lb));
  var color = user?.color ?? st.nextColor();

  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.viewInsetsOf(c).bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(user == null ? 'Thêm người dùng' : 'Sửa ${user.name}',
                style: Theme.of(c).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Tên'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: height,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Chiều cao', suffixText: 'cm', helperText: 'Để tính BMI'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: goal,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Mục tiêu', suffixText: unitLabel(lb), helperText: 'Bỏ trống = không đặt'),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: [
                for (final p in userPalette)
                  GestureDetector(
                    onTap: () => setS(() => color = p),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(p),
                        shape: BoxShape.circle,
                        border: Border.all(
                            width: color == p ? 3 : 0,
                            color: Theme.of(c).colorScheme.onSurface),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (user != null && st.users.length > 1)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(c).colorScheme.error),
                    onPressed: () => Navigator.pop(c, 'delete'),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Xoá người này'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(c, 'save'),
                  child: const Text('Lưu'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted) return;
  if (result == 'delete' && user != null) {
    final ok = await confirmDialog(context,
        title: 'Xoá ${user.name}?',
        message: 'Toàn bộ lịch sử cân của người này cũng bị xoá, không khôi phục được.');
    if (ok) await st.deleteUser(user.id!);
    return;
  }
  if (result != 'save') return;
  final n = name.text.trim();
  if (n.isEmpty) {
    toast(context, 'Tên đang trống, chưa lưu');
    return;
  }
  final h = double.tryParse(height.text.replaceAll(',', '.'));
  final g = double.tryParse(goal.text.replaceAll(',', '.'));
  final u = UserProfile(
    id: user?.id,
    name: n,
    heightCm: h != null && h > 50 && h < 260 ? h : null,
    goalKg: (user?.goalKg != null && goal.text.trim() == fmtW(user!.goalKg!, lb))
        ? user!.goalKg
        : (g != null && g > 0 ? fromUnit(g, lb) : null),
    goalStartKg: user?.goalStartKg,
    color: color,
  );
  await st.saveUser(u);
}
