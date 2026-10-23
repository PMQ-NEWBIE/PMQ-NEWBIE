import 'package:can_lo/metrics.dart';
import 'package:can_lo/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('BMI theo ngưỡng châu Á', () {
    expect(bmiBandAsia(18.4).level, 0);
    expect(bmiBandAsia(22.9).level, 1);
    expect(bmiBandAsia(23.0).level, 2);
    expect(bmiBandAsia(25.0).level, 3);
    expect(bmiBandAsia(30.0).level, 4);
  });

  test('Mifflin–St Jeor', () {
    // 10*70 + 6.25*175 - 5*25 + 5 = 1673.75
    expect(bmrMifflin(weightKg: 70, heightCm: 175, age: 25, sex: Sex.male), closeTo(1673.75, 0.01));
    // 10*55 + 6.25*160 - 5*30 - 161 = 1239
    expect(bmrMifflin(weightKg: 55, heightCm: 160, age: 30, sex: Sex.female), closeTo(1239, 0.01));
    expect(bmrMifflin(weightKg: 70, heightCm: null, age: 25, sex: Sex.male), isNull);
  });

  test('trung bình 7 ngày', () {
    final d = DateTime(2026, 10, 1);
    final h = [
      Measurement(weightKg: 70, at: d),
      Measurement(weightKg: 71, at: d.add(const Duration(days: 3))),
      Measurement(weightKg: 72, at: d.add(const Duration(days: 8))),
    ];
    expect(movingAverage(h, h[1].at), closeTo(70.5, 0.001));
    // ngày 8: chỉ còn lần ngày 3 và ngày 8 trong cửa sổ 7 ngày
    expect(movingAverage(h, h[2].at), closeTo(71.5, 0.001));
  });

  test('BMI bản ghi dùng chiều cao lúc cân', () {
    final m = Measurement(weightKg: 72, at: DateTime(2026), heightCm: 170);
    expect(m.bmi, closeTo(24.91, 0.01));
  });
}
