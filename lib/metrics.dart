import 'models.dart';

/// Phân loại BMI cho người châu Á.
/// Nguồn: WHO/IASO/IOTF, "The Asia-Pacific perspective: redefining obesity
/// and its treatment" (2000). Ngưỡng tạm thời, thấp hơn chuẩn quốc tế.
class BmiBand {
  final String label;
  final int level; // 0 thiếu cân, 1 bình thường, 2 thừa cân, 3 béo phì I, 4 béo phì II
  const BmiBand(this.label, this.level);
}

BmiBand bmiBandAsia(double bmi) {
  if (bmi < 18.5) return const BmiBand('Thiếu cân', 0);
  if (bmi < 23) return const BmiBand('Bình thường', 1);
  if (bmi < 25) return const BmiBand('Thừa cân', 2);
  if (bmi < 30) return const BmiBand('Béo phì độ I', 3);
  return const BmiBand('Béo phì độ II', 4);
}

const bmiSource = 'Ngưỡng châu Á–Thái Bình Dương (WHO/IASO/IOTF 2000)';

/// Năng lượng nghỉ (kcal/ngày) theo Mifflin–St Jeor.
/// Nguồn: Mifflin MD, St Jeor ST et al., Am J Clin Nutr 1990;51(2):241–7.
double? bmrMifflin({
  required double weightKg,
  required double? heightCm,
  required int? age,
  required Sex? sex,
}) {
  if (heightCm == null || age == null || sex == null) return null;
  if (age < 10 || age > 110) return null;
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return sex == Sex.male ? base + 5 : base - 161;
}

const bmrSource = 'Mifflin–St Jeor (1990)';

/// Trung bình các lần cân trong [days] ngày tính tới thời điểm [at] (gồm cả [at]).
/// Cân nặng dao động 1–2 kg/ngày do nước và thức ăn, nên xem số trung bình
/// mới thấy xu hướng thật.
double? movingAverage(List<Measurement> history, DateTime at, {int days = 7}) {
  final from = at.subtract(Duration(days: days));
  var sum = 0.0;
  var n = 0;
  for (final m in history) {
    if (m.at.isAfter(from) && !m.at.isAfter(at)) {
      sum += m.weightKg;
      n++;
    }
  }
  return n == 0 ? null : sum / n;
}

/// Buổi trong ngày, để so các lần cân cùng giờ với nhau.
String dayPart(DateTime t) {
  final h = t.hour;
  if (h < 4) return 'Đêm';
  if (h < 11) return 'Sáng';
  if (h < 14) return 'Trưa';
  if (h < 18) return 'Chiều';
  return 'Tối';
}
