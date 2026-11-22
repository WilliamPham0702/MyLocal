# MyLocal – app giả lập vị trí iPhone (bản Việt hóa từ Locus)

Dựa trên Locus (https://github.com/ChrisMack32/Locus, giấy phép MIT – xem LICENSE-Locus).
Repo này chỉ chứa phần thay đổi (`overlay/`). Khi build, GitHub Actions tải Locus gốc về, chép đè overlay rồi build ra IPA chưa ký.

## Đã thay đổi so với Locus gốc
- Giao diện tiếng Việt, tên app hiển thị "MyLocal", bundle ID `com.phamnhutthanh.mylocal`
- Ô tìm kiếm nhận tọa độ: gõ `10.7769, 106.7009` (vĩ độ, kinh độ) → bấm "Đi tới tọa độ"

## 1. Build IPA
1. Tạo repo mới trên GitHub, upload toàn bộ thư mục này (nhớ có thư mục `.github`).
2. Tab **Actions** → **Build IPA chua ky** → **Run workflow**.
3. Chạy xong (khoảng 5–10 phút) → mở lần chạy → mục **Artifacts** → tải `MyLocal-unsigned` (file zip chứa `MyLocal.ipa`).
4. Giải nén, ký và cài bằng SideStore.

## 2. Chuẩn bị trên iPhone (iOS 26)
1. Bật **Developer Mode**: Cài đặt › Quyền riêng tư & Bảo mật › Chế độ nhà phát triển.
2. Tạo file **RPPairing** (làm 1 lần, cần máy tính Windows/Mac/Linux):
   - Tải idevice_pair: https://github.com/jkcoxson/idevice_pair/releases
   - Cắm iPhone, mở khóa, bấm Tin cậy → tạo file ở chế độ **RPPairing**.
   - Lưu ý: file `.mobiledevicepairing` của SideStore **không dùng được**.
3. Gửi file RPPairing vào iPhone (AirDrop/Zalo/Files) → mở app MyLocal → Nhập file pairing (hoặc sao chép nội dung rồi bấm Dán).
4. Cài **LocalDevVPN** từ App Store, bật lên, giữ IP mặc định `10.7.0.1`.

## 3. Sử dụng
- Chạm bản đồ để thả ghim, hoặc tìm địa chỉ / nhập tọa độ → **Dịch chuyển**.
- Ngôi sao trên bản đồ: lưu điểm yêu thích (xem lại ở nút ngôi sao dưới thanh công cụ).
- **Dừng**: trả về vị trí thật.
- Lần dịch chuyển đầu tiên nên dùng Wi‑Fi.

## Nếu build lỗi
- Lỗi về Xcode/SDK hoặc file `AppIcon.icon`: đổi `runs-on: macos-15` thành `runs-on: macos-26` trong `.github/workflows/build-ipa.yml`.
- Lỗi khác: copy log bước bị đỏ gửi lại để sửa.
