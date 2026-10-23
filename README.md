# Cân Lỏ

App Android đọc cân điện tử Bluetooth, không quảng cáo, dữ liệu nằm trong máy.

- **Tải app:** mục [Releases](../../releases/latest), lấy `CanLo.apk` (máy 64-bit, gần như mọi máy đời mới). Máy 32-bit rất cũ lấy `CanLo-armv7.apk`.
- **Trang dò sóng trên web:** thư mục `docs/`.

## Hỗ trợ cân

| Kiểu | Cách nhận số | Chạy nền |
|---|---|---|
| Xiaomi Mi Scale 1 / 2 | Nghe quảng bá, không cần kết nối | Có |
| Bluetooth Weight Scale chuẩn (0x181D) | Kết nối GATT, đồng bộ bản ghi cân còn lưu | Không cần (mở app là đồng bộ) |
| Cân lạ không mã hoá | Dò byte trong app: nhập số trên màn hình cân, chọn vị trí khớp | Có |

## Cách chốt số (`lib/session.dart`)

Mỗi lần đứng lên cân là một phiên. Số được chốt khi:
1. cân tự báo "đã ổn định", hoặc
2. số đứng yên (lệch ≤ 0,1 kg) đủ 1,5 giây với ít nhất 2 gói, hoặc
3. phiên kết thúc (bước xuống, hoặc cân im 4 giây) mà chưa chốt: lấy số giữ lâu nhất.

Cùng logic có bản Kotlin trong `android_overrides/ScaleService.kt` cho chế độ chạy nền (chạy không cần Flutter engine). Sửa logic thì sửa cả hai, test ở `test/session_test.dart`.

## Dữ liệu mỗi lần cân

Cân nặng, thời gian, người cân, thiết bị, nguồn (nghe sóng / kết nối / chạy nền / nhập tay), cách chốt, độ tin cậy, số gói, thời gian đứng, dao động thấp nhất–cao nhất, trở kháng (nếu cân gửi), chiều cao lúc cân, ghi chú, byte thô.
Tính thêm khi xem: chênh lần trước, trung bình 7 ngày, BMI theo ngưỡng châu Á (WHO/IASO/IOTF 2000), năng lượng nghỉ Mifflin–St Jeor (1990).

## Build

GitHub Actions tự build mỗi lần push (`.github/workflows/build.yml`): `flutter create` sinh khung Android, chép code native, icon và manifest trong `android_overrides/`, chạy `flutter analyze` + `flutter test`, rồi build APK tách theo chip.
Build lỗi thì log được đẩy lên nhánh `ci-logs`.

Khoá ký `android_overrides/debug.keystore` cố định để cài đè không mất dữ liệu. Đây là khoá cho app cá nhân, không dùng để phát hành lên Store.
