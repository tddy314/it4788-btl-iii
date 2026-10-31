# Mục 1 — nền tảng, xác thực và cài đặt tài khoản

Cập nhật 31/10/2026. Tiếp tục dùng khung/core đã có, chỉ thêm `features/auth`, `features/settings` và nối ở `main.dart`. Không triển khai bảng tin, hồ sơ, bạn bè, câu hỏi, chat hoặc thông báo.

## Luồng chạy

- Chưa có phiên → màn đăng nhập tiếng Việt, email/mật khẩu, hiện/ẩn mật khẩu, thông báo liên hệ giảng viên nếu chưa có tài khoản/quên mật khẩu. Không có đăng ký/OTP/reset qua API admin.
- Đăng nhập → `auth/login` với `email`, mật khẩu giữ nguyên, `device_id` UUID cài đặt và `platform: ANDROID`. UUID được lưu secure storage, không sinh lại cho mỗi login. Không lưu mật khẩu vào app storage.
- Token được kiểm tra cấu trúc rồi lưu qua `SessionStore`; router chung tự mở shell. Lần mở sau khôi phục phiên sẵn có, không yêu cầu API thành công trước khi vào shell offline.
- Tab Cá nhân tạm hiển thị menu cài đặt tài khoản: đổi mật khẩu, đăng xuất, giới thiệu và đóng app. Đây không phải màn hồ sơ cá nhân.
- Đổi mật khẩu gọi `auth/change-password` với `old_password`, `new_password`; xác nhận mật khẩu mới ở client trước khi gọi mạng. Chỉ báo thành công sau response hợp lệ. Hủy request khi rời màn, không lưu password vào draft/cache.
- Refresh token gắn qua callback chung. Lỗi mạng giữ phiên; server xác nhận refresh không hợp lệ thì xóa phiên và trở về login. Không tự replay thao tác ghi. Logout online cố gắng gọi server rồi xóa phiên trên máy; logout offline vẫn xóa cục bộ và thông báo chưa xác nhận thu hồi trên server.

## Các điểm cần nhóm tích hợp tiếp

`AuthApplication` là điểm composition cho nhóm. Bổ sung builder cho `AppTab.feed`, `questionBank`, `friends`, `notifications` tại đây khi các feature sẵn sàng; giữ `loginBuilder` và refresh callback. Khi làm hồ sơ, thay builder `AppTab.profile` bằng màn hồ sơ và thêm nút mở `SettingsRoutes.settings`; không viết lại auth hoặc sửa router chung.

`SettingsRoutes.changePassword` có thể được mở từ menu khác bằng `Navigator.pushNamed`. Cài đặt thông báo và danh sách chặn thuộc thành viên tương ứng, chưa có màn/nút giả trong menu này. Không gọi API admin để cấp tài khoản hoặc gán dữ liệu demo.

Mật khẩu chỉ kiểm tra không rỗng, xác nhận khớp và khác mật khẩu hiện tại khi đổi. Chưa tự áp quy tắc độ dài/đặc biệt vì Swagger hiện chỉ bắt buộc có dữ liệu và còn dùng ví dụ có ký tự đặc biệt, khác mô tả PDF cũ. Quy tắc server được ưu tiên khi xác nhận tích hợp. Không hardcode domain trường nếu chưa có danh sách email được chấp nhận.

Core hiện gom mã lỗi về `AppFailure`; repository auth bổ sung lời nhắc cho HTTP 400/403 nhưng không sửa core, không hiển thị nguyên exception/server body có thể chứa dữ liệu nhạy cảm. Lỗi API chưa có mapping chi tiết giữ thông báo chung. Firebase FID là optional, chưa gửi FID giả; việc đăng ký push vẫn chờ phần thông báo.

## Kiểm thử và giới hạn

Đã chạy 29 test gồm 18 test khung cũ và 11 test auth mới: validation trước mạng, giữ password nguyên trạng, UUID ổn định, chống login lặp, login sai/bị khóa/response hỏng, offline, refresh bị từ chối, logout offline, payload/timeout đổi mật khẩu, giữ input khi lỗi và màn hình nhỏ/font lớn. Thêm một test luồng UI đăng nhập → mở cài đặt → đổi mật khẩu → đăng xuất đạt, tổng 30 test. `flutter analyze --no-pub` sạch lỗi.

Build Android đã được xử lý ngày 31/10/2026:

- NDK `28.2.13676358` cài dở chỉ có `.installer`; đã chuyển thư mục cũ sang bản sao lưu `sdk/ndk-incomplete-28.2.13676358` rồi để Gradle cài lại. SDK Platform 35/36 và CMake 3.22.1 cũng đã được cài theo yêu cầu plugin.
- Sau đó gặp lỗi Kotlin incremental cache do project ở D: còn Pub cache ở C:. Đã đặt `kotlin.incremental=false` trong `android/gradle.properties`; không đổi mã feature/core. Cấu hình này tắt biên dịch Kotlin tăng dần, có thể khiến bước biên dịch Kotlin các lần sau chậm hơn. Tham khảo [tài liệu Kotlin](https://kotlinlang.org/docs/gradle-compilation-and-caches.html).
- `flutter run -d emulator-5554 --no-resident` đã build thành công `build/app/outputs/flutter-apk/app-debug.apk` cho x86_64, cài và mở app trên emulator Android API 37. Sau bản sửa success code, đã đăng nhập với server thật bằng tài khoản người dùng cung cấp và kiểm tra vào khung 5 tab bằng ảnh màn hình. Chưa kiểm thử thiết bị thật/ARM64.
- Khi phát triển tiếp, dùng `flutter run -d emulator-5554` để giữ kết nối hot reload. Chưa cần `flutter clean` hoặc cài lại SDK nếu không có lỗi mới.

Các test tự động dùng transport/storage giả, không chứa tài khoản thật. Đăng nhập trên emulator đã kiểm chứng riêng với server thật; refresh/logout/đổi mật khẩu thật vẫn chưa xác nhận. Cần thử trên Android thật với ngắt mạng, đóng/mở app, thu hồi phiên và storage plugin. Không kiểm chứng các tính năng còn placeholder bằng các test này.

### Sửa lỗi đăng nhập theo phản hồi server thật

Ngày 31/10/2026, đã thử request với tài khoản do người dùng cung cấp: payload ANDROID trả HTTP 200, `code: "1000"` và cả access token/refresh token. Payload WEB có thể trả refresh token null; không đổi Android sang chấp nhận token thiếu dựa trên kết quả WEB.

Nguyên nhân app báo lỗi dù server chấp nhận tài khoản là `AppConfig.successCode` trước đó dùng ví dụ `0000` trong Swagger. Đã sửa mặc định thành `1000`, cập nhật fixture và thêm test hồi quy để chỉ mã thành công đã cấu hình được chấp nhận (tổng 31 test đạt). Không hardcode tài khoản/password/token thật trong source hoặc test. Refresh/logout/đổi mật khẩu trên server thật vẫn cần kiểm chứng riêng.

Chạy:

```sh
flutter run
flutter analyze --no-pub
flutter test --no-pub
```

Sau login, bảng tin vẫn là vùng trống chờ thành viên 2. Khả năng cache bài offline hiện là hạ tầng, chưa có dữ liệu feed để nghiệm thu.
