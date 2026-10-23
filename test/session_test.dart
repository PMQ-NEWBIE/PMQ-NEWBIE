import 'package:can_lo/models.dart';
import 'package:can_lo/protocols.dart';
import 'package:can_lo/session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 10, 23, 7, 0, 0);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

  test('cân báo ổn định thì chốt ngay', () {
    final s = WeighSession();
    expect(s.feed(Reading(68.0), at(0)).commit, isNull);
    final step = s.feed(Reading(68.4, stable: true), at(300));
    expect(step.commit, isNotNull);
    expect(step.commit!.method, CommitMethod.scaleStable);
    expect(step.commit!.kg, 68.4);
    expect(step.commit!.samples, 2);
    expect(step.commit!.minKg, 68.0);
    expect(step.commit!.maxKg, 68.4);
  });

  test('số đứng yên 1,5 giây thì chốt kiểu hold', () {
    final s = WeighSession();
    SessionCommit? c;
    for (var i = 0; i <= 6; i++) {
      c ??= s.feed(Reading(70.05 + (i.isEven ? 0.0 : 0.05)), at(i * 300)).commit;
    }
    expect(c, isNotNull);
    expect(c!.method, CommitMethod.hold);
    expect(c.durationMs, greaterThanOrEqualTo(1500));
  });

  test('chưa chốt mà cân im lặng thì lấy số giữ lâu nhất', () {
    final s = WeighSession(silence: const Duration(seconds: 4));
    s.feed(Reading(60.0), at(0));
    s.feed(Reading(65.0), at(300));
    s.feed(Reading(66.2), at(600));
    s.feed(Reading(66.2), at(1000)); // giữ 400ms
    s.feed(Reading(67.0), at(1100));
    expect(s.checkSilence(at(3000)), isNull);
    final c = s.checkSilence(at(6000));
    expect(c, isNotNull);
    expect(c!.method, CommitMethod.sessionEnd);
    expect(c.kg, 66.2);
    expect(s.active, isFalse);
  });

  test('bước xuống (cờ removed) kết thúc phiên và chốt', () {
    final s = WeighSession();
    s.feed(Reading(55.0), at(0));
    s.feed(Reading(55.0), at(500));
    final step = s.feed(Reading(55.0, removed: true), at(900));
    expect(step.ended, isTrue);
    expect(step.commit?.kg, 55.0);
    expect(step.commit?.method, CommitMethod.sessionEnd);
  });

  test('cân phát lại số cũ (không về 0, không tăng dần) thì không lưu trùng', () {
    final s = WeighSession(silence: const Duration(seconds: 4));
    expect(s.feed(Reading(80.0, stable: true), at(0)).commit, isNotNull);
    expect(s.checkSilence(at(6000)), isNull); // cân tắt, phiên kết thúc
    expect(s.feed(Reading(80.0, stable: true), at(10000)).commit, isNull);
  });

  test('bước xuống rồi cân lại đúng số cũ vẫn được lưu', () {
    final s = WeighSession();
    expect(s.feed(Reading(76.95, stable: true), at(0)).commit, isNotNull);
    s.feed(Reading(0.0), at(2000)); // cân về 0
    expect(s.feed(Reading(76.95, stable: true), at(10000)).commit, isNotNull);
  });

  test('cân lại có đoạn số tăng dần vẫn được lưu dù cân không về 0', () {
    final s = WeighSession(silence: const Duration(seconds: 4));
    for (var i = 0; i <= 6; i++) {
      s.feed(Reading(76.95), at(i * 300));
    }
    s.checkSilence(at(8000));
    s.feed(Reading(40.0), at(9000));
    SessionCommit? c;
    for (var i = 0; i <= 6; i++) {
      c ??= s.feed(Reading(76.95), at(9300 + i * 300)).commit;
    }
    expect(c, isNotNull);
  });

  test('bỏ qua số nhỏ hơn 5 kg', () {
    final s = WeighSession();
    final step = s.feed(Reading(3.0, stable: true), at(0));
    expect(step.commit, isNull);
    expect(s.active, isFalse);
  });

  test('bấm lưu tay khi đang đo', () {
    final s = WeighSession();
    s.feed(Reading(72.3), at(0));
    final c = s.forceCommit(at(200));
    expect(c?.method, CommitMethod.liveButton);
    expect(c?.kg, 72.3);
  });
}
