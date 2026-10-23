# Cân Lỏ

App Android đọc cân điện tử Bluetooth, không quảng cáo, dữ liệu nằm trong máy.

- **Tải app:** vào mục [Releases](../../releases/latest), tải `CanLo.apk`.
- **Trang dò sóng trên web:** thư mục `docs/` (GitHub Pages).

## Hỗ trợ cân

| Kiểu | Cách nhận số |
|---|---|
| Xiaomi Mi Scale 1 / 2 | Nghe quảng bá, không cần kết nối |
| Bluetooth Weight Scale chuẩn (0x181D) | Kết nối GATT, đồng bộ bản ghi cân còn lưu |
| Cân lạ không mã hoá | Dò byte trong app: nhập số trên màn hình cân, chọn vị trí khớp |

## Build

GitHub Actions tự build mỗi lần push lên `main` (`.github/workflows/build.yml`):
`flutter create` sinh khung Android, chép code native trong `android_overrides/`, rồi `flutter build apk --release`.
