import 'package:can_lo/protocols.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 68.4 kg * 200 = 13680 = 0x3570
  test('Mi Scale 1: kg, cờ ổn định', () {
    final r = parseMi1([0x22, 0x70, 0x35, 0xEA, 0x07, 10, 23, 7, 0, 0])!;
    expect(r.kg, closeTo(68.4, 0.001));
    expect(r.stable, isTrue);
    expect(r.removed, isFalse);
  });

  test('Mi Scale 1: cờ bước xuống', () {
    final r = parseMi1([0xA2, 0x70, 0x35])!;
    expect(r.removed, isTrue);
  });

  test('Mi Scale 2: kg + trở kháng', () {
    final b = [0x02, 0x26, 0xEA, 0x07, 10, 23, 7, 0, 0, 0xF4, 0x01, 0x70, 0x35];
    final r = parseMi2(b)!;
    expect(r.kg, closeTo(68.4, 0.001));
    expect(r.stable, isTrue);
    expect(r.impedance, 500);
  });

  test('Weight Measurement chuẩn 0x2A9D', () {
    final r = parseWeightMeasurement([0x00, 0x70, 0x35])!;
    expect(r.kg, closeTo(68.4, 0.001));
    expect(parseWeightMeasurement([0x00, 0xFF, 0xFF]), isNull);
  });

  test('dò byte tìm đúng vị trí và hệ số', () {
    final p = AdvPacket({0x1234: [0x00, 0x70, 0x35, 0x00]}, {}, []);
    final c = findCandidates(p, 68.4);
    expect(c.first.match, isTrue);
    expect(c.first.cfg.offset, 1);
    expect(c.first.cfg.bigEndian, isFalse);
    expect(c.first.cfg.divisor, 200);
    final back = parseLearned(p, c.first.cfg)!;
    expect(back.kg, closeTo(68.4, 0.001));
  });

  test('chuẩn hoá UUID', () {
    expect(normUuid('181D'), '0000181d-0000-1000-8000-00805f9b34fb');
    expect(shortUuid('0000181d-0000-1000-8000-00805f9b34fb'), '0x181D');
  });

  test('nhận diện kiểu cân từ gói quảng bá', () {
    final mi2 = AdvPacket({}, {svcBodyComp: List.filled(13, 0)}, []);
    expect(detectProto(mi2), isNotNull);
    expect(detectProto(AdvPacket({}, {}, [])), isNull);
  });
}
