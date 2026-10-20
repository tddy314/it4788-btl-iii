# Khung app và thành phần dùng chung

## Phạm vi đã triển khai

Chỉ code trong `lib/app`, `lib/core` và entrypoint `lib/main.dart`. Các thư mục `lib/features/*` vẫn giữ `.gitkeep`, chưa triển khai đăng nhập, bảng tin, bài viết, câu hỏi, chat hay nghiệp vụ khác.

- `app`: bootstrap có loading/thử lại khi lỗi, dependency injection qua `AppScope`, theme/màu tập trung, locale tiếng Việt, router bảo vệ nội dung và shell 5 tab.
- `core/config`: cấu hình base URL HTTPS, timeout và mã thành công của API.
- `core/network`: API client dùng Dio, Bearer token, envelope, mapping lỗi, hủy request; monitor trạng thái mạng; điểm nối cho refresh token.
- `core/storage`: secure token storage, JSON cache nhỏ theo tài khoản, bản nháp bảo mật, controller cache-first giữ dữ liệu khi refresh thất bại do mạng.
- `core/media`: upload multipart với purpose/giới hạn dung lượng, tiến trình và hủy; chưa có camera/picker hoặc validation video theo nghiệp vụ.
- `core/widgets`: button chống bấm khi busy, text field, loading/empty/error, banner offline, ảnh cache/avatar và view cho dữ liệu cache.
- `core/validation`: kiểm tra bắt buộc và đếm/giới hạn số từ.
- Android: quyền Internet/network state, tên SQB, tắt backup để tránh phục hồi khóa/token không đồng bộ.

Lúc chạy lần đầu chỉ hiện màn hình chờ tích hợp đăng nhập, không có form giả hoặc tài khoản hardcode. Khi có phiên, shell hiện 5 tab rỗng. Đây là các vị trí gắn feature, không phải homepage đã hoàn thiện.

## Gắn feature vào khung

Lấy dependencies bằng `AppScope.of(context)`. Không tạo API client/token store riêng trong feature. `SqbApp` nhận `loginBuilder`, `tabBuilders` theo `AppTab`, và `protectedRoutes` để đăng ký màn hình; route con nhận ID qua `ModalRoute.of(context)?.settings.arguments`.

Người làm auth phải gọi API đăng nhập bằng `authenticated: false`, chuyển response thành `SessionTokens` (user ID dùng chuỗi), và `await dependencies.session.save(tokens)`. Router tự chuyển sang shell; `session.clear()` bỏ navigation stack của phiên cũ. Việc có token lưu trên máy chỉ cho phép mở dữ liệu offline, không thay thế xác thực của server.

Đăng ký `dependencies.api.refreshTokens = (current) async { ... }` ở phần auth. Callback gọi endpoint refresh với `authenticated: false`, trả về cặp token mới và giữ đúng user ID; không tự gọi `session.save()` trong callback vì API client đã làm việc này. Lỗi mạng phải được giữ nguyên, không tự logout. Khi refresh được server xác nhận không hợp lệ, auth xử lý yêu cầu đăng nhập lại. Client gom các refresh đồng thời và chỉ gửi lại GET/HEAD một lần; thao tác ghi/upload không được tự replay.

Ví dụ gọi endpoint mới từ repository:

```dart
final result = await dependencies.api.get(
  'resource', // đường dẫn tương đối sau /api/v1/, không gắn lại prefix
  decode: (data) => MyModel.fromJson(data as Map<String, dynamic>),
);
```

`ApiClient.request` hỗ trợ method, data, query, CancelToken và upload progress. Mọi request đi qua client này cần envelope `{code, message, data}`; không dùng nó cho tải file binary hoặc upload presigned sang domain khác. Không có log chứa token/password. Client không tự gọi endpoint nghiệp vụ lúc khởi động.

## Mất mạng, cache và bản nháp

`ConnectionMonitor.available` chỉ có nghĩa thiết bị có mạng Wi-Fi/mobile. Từng request vẫn phải xử lý timeout, DNS, server lỗi và response sai. Monitor được kiểm tra lại khi app trở về foreground và trước request. Không polling/retry liên tục, không tự đăng xuất vì offline.

Repository màn chỉ đọc có thể dùng `CachedResourceController<T>` với cache, user ID, tên resource, fetch, encode/decode. Gọi `load()` một lần khi khởi tạo và khi refresh; controller đọc cache trước, giữ dữ liệu khi offline/timeout/server lỗi, chặn load đồng thời và không notify sau dispose. `CachedResourceView` hiển thị nội dung cùng lỗi refresh thay vì thay toàn bộ nội dung bằng trang lỗi. Feature vẫn phải tự xây pull-to-refresh, phân trang và cách ghép bản ghi.

- Mỗi controller chỉ thuộc một user; dispose khi rời màn hoặc đổi phiên. Chỉ đọc cache sau khi có phiên, không mở cache cho khách.
- Cache JSON là dữ liệu nhỏ, không nhạy cảm, giới hạn mặc định 512 KiB/record. Feature giới hạn số bài đã lưu; không lưu cả lịch sử vô hạn hoặc nội dung riêng tư trong preferences.
- Ảnh dùng `AppNetworkImage`; chỉ ảnh đã tải/lưu thành công mới có khả năng xem offline. Media cache có thể bị hệ điều hành hoặc chính sách dọn cache xóa; không hứa ảnh chưa tải sẽ có sẵn.
- Bản nháp dùng `dependencies.drafts` theo user/name, nằm trong secure storage. Feature lưu/khôi phục/xóa chủ động; khi timeout không xóa draft hoặc tự gửi lại. Đường dẫn file tạm không bảo đảm sống qua lần khởi động tiếp theo, cần sao chép media nháp sang nơi bền vững ở feature media sau này.
- Không dùng cache để che lỗi 401/403. Các lỗi này cần xử lý quyền/phiên, khác với offline.

Chưa thể demo “bài viết còn hiển thị khi ngắt mạng” cho đến khi feature feed dùng cơ chế cache và ảnh này. Kiểm thử hiện xác nhận hành vi nền tảng bằng repository/transport giả, không thay cho nghiệm thu API thật trên điện thoại.

## Chạy và cấu hình

```sh
flutter pub get
flutter run
flutter analyze
flutter test
```

Mặc định API là `https://snsqb.duckdns.org/api/v1/`, mã thành công `0000`. Chỉ đổi mã sau khi kiểm chứng server thật; PDF cũ ghi `1000` nên có cấu hình riêng:

```sh
flutter run --dart-define=API_BASE_URL=https://snsqb.duckdns.org/api/v1/ --dart-define=API_SUCCESS_CODE=0000
```

Không đưa token hoặc mật khẩu vào dart-define, source code, fixture hay Git. Hạ tầng này chưa có cấu hình Firebase/STOMP, đăng nhập thật, quản lý camera, hay chức năng tự gửi lại thao tác offline.

## Kiểm chứng

- Đã chạy `flutter analyze --no-pub` và bộ kiểm thử nền tảng: transport lỗi, refresh đồng thời, session/logout, cache offline, router guard và widget trạng thái.
- Chưa kiểm thử API có đăng nhập thật hoặc máy Android thật. Build APK debug đã thử nhưng dừng ở bước tải Android engine artifacts của Flutter SDK; chưa có APK được xác nhận build thành công.

Tham khảo hợp đồng thư viện: [Dio](https://pub.dev/packages/dio), [Connectivity Plus](https://pub.dev/packages/connectivity_plus), [Secure Storage](https://pub.dev/packages/flutter_secure_storage), [Shared Preferences](https://pub.dev/packages/shared_preferences), [Cached Network Image](https://pub.dev/packages/cached_network_image).
