# Kiểm tra bản tích hợp ngày 17/11/2026

> Đây là báo cáo phát hiện trước khi sửa. Trạng thái bản sửa và kiểm chứng mới nhất xem [bàn giao hoàn thiện luồng](hoan-thien-luong-2026-11-17.md); không coi các mục bên dưới là danh sách lỗi còn nguyên sau đợt sửa.

## Phạm vi và kết luận

Rà soát nhánh `feat1`, commit `0b30ad9` sau khi nhận `main`: khung app, auth/settings, feed/posts, hồ sơ/quan hệ, ngân hàng câu hỏi, chat/thông báo, cấu hình Android và kiểm thử. Đây là kiểm tra mã, hợp đồng API và kiểm thử tự động; **chưa phải nghiệm thu toàn bộ tính năng trên điện thoại thật**. Không sửa implementation feature, không gửi tin/đăng bài/đổi mật khẩu hay tác động dữ liệu server trong đợt kiểm tra này.

Phân tích mã và bộ test hiện có đạt nhưng vẫn có lỗi vận hành, tập trung ở chat/thông báo. Ưu tiên xử lý các mục P1 trước, sau đó kiểm thử mất mạng và đổi phiên trên thiết bị.

## Kết quả chạy kiểm tra

| Kiểm tra | Kết quả |
| --- | --- |
| `flutter pub get` | Thành công; không chủ động nâng phiên bản dependency |
| `dart format --output=none --set-exit-if-changed lib test` | 124 file, không cần đổi định dạng |
| `flutter analyze --no-pub` | Không phát hiện vấn đề |
| `flutter test --no-pub --timeout 45s` | 144 test đạt |
| 8 phép thử bổ sung bằng fake, không gọi server | Tái hiện được cả 8 hành vi lỗi mô tả bên dưới |
| `flutter build apk --debug --no-pub --target-platform android-x64` | Thành công, tạo `build/app/outputs/flutter-apk/app-debug.apk` (Gradle khoảng 578 giây) |
| Cài APK lên `emulator-5554` và mở app | Cài thành công; sau khi dừng/mở lại app đã hiển thị màn đăng nhập; không thấy lỗi Flutter/AndroidRuntime trong phần log lỗi đã đọc |

Log cục bộ nằm trong `.dart_tool/audit-*.log`; OpenAPI tải trong đợt kiểm tra ở `.dart_tool/audit-openapi.json`. Mã probe ở `.dart_tool/audit_regression_test.dart`, nằm ngoài bộ test được commit. Các probe **assert hành vi lỗi đang tồn tại**, vì vậy kết quả probe đạt không có nghĩa app đã được sửa. Khi sửa, cần viết test hồi quy theo hành vi đúng vào bộ test chính.

Lần mở ngay sau cài đặt ban đầu hiển thị trắng; log có cảnh báo bỏ nhiều frame. Sau khi dừng/mở lại riêng app, màn đăng nhập hiển thị bình thường. Chưa xác định nguyên nhân của lần mở chậm, không kết luận là lỗi logic app hay lỗi máy ảo. Chưa đăng nhập/gọi các API nghiệp vụ trên máy ảo trong đợt này. Ảnh kiểm tra cục bộ: `.dart_tool/audit-launch.png`.

## Phát hiện cần sửa

### P1 — Chat chấp nhận chứng chỉ TLS không hợp lệ

- Vị trí: `lib/features/chat/data/stomp_client.dart:115`.
- `badCertificateCallback` luôn trả `true`, vô hiệu hóa kiểm tra chứng chỉ không hợp lệ cho kết nối WebSocket có mang token.
- Kết luận từ mã nguồn, chưa thử tấn công mạng. Cần dùng xác minh chứng chỉ mặc định; không giải quyết lỗi kết nối bằng cách chấp nhận mọi chứng chỉ.

### P1 — Rời màn hoặc logout không giải phóng kết nối chat

- Vị trí: `lib/features/chat/presentation/chat_detail_screen.dart:93`, `lib/features/chat/controllers/chat_detail_controller.dart:528`, `lib/features/chat/presentation/conversations_screen.dart:62`.
- Mỗi màn tạo repository/socket riêng. Dispose màn chỉ dispose controller; controller chi tiết chỉ hủy timer, controller hội thoại không có cleanup riêng. Không gọi unsubscribe/dispose socket do các màn sở hữu.
- Socket, callback và cơ chế reconnect có thể tiếp tục hoạt động sau khi rời màn/đăng xuất, tạo nhiều kết nối khi mở lại màn. Phần reconnect còn lặp mỗi 5 giây, chưa phân biệt lỗi xác thực.
- Cần quản lý quyền sở hữu kết nối và đóng/hủy đúng vòng đời, gắn với phiên; không chỉ thêm `mounted` vào widget.

### P2 — Response về sau dispose gây lỗi ở chat và thông báo

- Vị trí: `lib/features/chat/controllers/chat_detail_controller.dart:196`, `lib/features/notifications/controllers/notification_controller.dart:48`, tương tự ở controller hội thoại.
- Không có guard disposed/generation/phiên sau các đoạn `await`; `finally` vẫn `notifyListeners()`.
- Đã tái hiện bằng hai probe: giữ request bằng `Completer`, dispose controller, trả response. Cả hai phát sinh `FlutterError` do sử dụng notifier đã dispose.
- Cần bỏ response hết hiệu lực, ngăn tạo listener sau khi màn đã đóng và hủy request phù hợp. Assertion debug không đồng nghĩa release sẽ crash giống hệt; công việc nền và response cũ vẫn là lỗi cần xử lý.

### P2 — Báo tin nhắn đã gửi trước khi được server xác nhận

- Vị trí: `lib/features/chat/controllers/chat_detail_controller.dart:361`, `:417`, `:475`, `:509`.
- Sau lời gọi gửi STOMP trả `void`, controller chuyển ngay sang `MessageStatus.sent`; chưa chờ ID/broadcast/ack từ server. Bản nháp text bị xóa trước đó.
- Đã tái hiện: socket fake ở trạng thái connected, không có phản hồi server; tin vẫn chuyển sang sent, `messageId` rỗng.
- Khi server từ chối hoặc mạng đứt sau khi ghi socket, giao diện có thể báo thành công sai. Cần đối soát với xác nhận server; timeout phải giữ trạng thái chưa rõ kết quả, không tự gửi lại thao tác ghi.

### P2 — Gửi lại ảnh tạo thêm bubble và bỏ bubble cũ ở trạng thái đang gửi

- Vị trí: `lib/features/chat/controllers/chat_detail_controller.dart:484`.
- `retryFailedMessage` đổi bản ghi cũ thành sending rồi gọi `sendImageMessage`, hàm này sinh ID mới và chèn bản ghi mới.
- Đã tái hiện upload lỗi → thử lại: danh sách có 2 bubble, bubble gốc vẫn sending. Nhánh GIF cũng đi vào retry ảnh và coi URL remote là đường dẫn file.
- Cần retry/đối soát trên cùng bản ghi, phân biệt file local với URL đã upload, tránh upload/gửi lặp khi chưa xác định kết quả lần trước.

### P2 — Hai tin hợp lệ có cùng nội dung bị gộp mất

- Vị trí: `lib/features/chat/controllers/chat_detail_controller.dart:154`.
- Ngoài ID, logic còn gộp hai tin do mình gửi có cùng nội dung trong 30 giây, kể cả chúng có hai ID server khác nhau.
- Đã tái hiện hai sự kiện “OK” có `message_id` 11 và 12: chỉ còn 1 tin. Ảnh có nội dung chung cũng chịu quy tắc này.
- Cần đối soát theo định danh được backend hỗ trợ; không dùng nội dung làm bằng chứng hai tin là một.

### P2 — Realtime chat lệch OpenAPI và chưa phân loại sự kiện

- Vị trí: `lib/features/chat/data/chat_repository.dart:175`, `lib/features/chat/controllers/chat_detail_controller.dart:84`, `lib/features/chat/controllers/conversations_controller.dart:65`.
- OpenAPI tải ngày 17/11 ghi payload `/app/chat.typing` dùng `typing`; code dùng `is_typing`.
- OpenAPI mô tả tin nhắn, typing, read receipt và thu hồi cùng về `/user/queue/messages`. Code nhận mọi payload của queue thành tin nhắn, đồng thời nghe typing/read ở `/topic/conv.<id>.typing` và `.read` không được mô tả trong tài liệu hiện tại.
- Đã tái hiện queue nhận payload read receipt: controller chèn một tin nội dung rỗng. Controller hội thoại cũng tăng unread trên mọi sự kiện của queue, chưa phân loại sự kiện hoặc loại sự kiện của chính mình.
- Cần đối chiếu mẫu sự kiện backend thật trong phạm vi được phép và dispatch theo loại sự kiện; chưa khẳng định server hiện tại hỗ trợ/không hỗ trợ các topic ngoài tài liệu. Không suy ra `client_msg_id` được server hỗ trợ chống trùng chỉ vì client gửi trường này.

### P2 — Tin gửi thất bại biến thành đã gửi sau khi đọc cache

- Vị trí: `lib/features/chat/models/chat_message.dart:99`, `lib/features/chat/data/chat_repository.dart:253`.
- `toJson` lưu `status`, nhưng `fromJson` luôn đặt `MessageStatus.sent`; cùng parser được dùng đọc cache.
- Đã tái hiện failed → JSON → đọc lại thành sent. Sau đó refresh có thể loại bỏ tin cục bộ vì controller chỉ giữ bản ghi sending/failed.
- Cần phân biệt DTO server với bản lưu cục bộ hoặc phục hồi trạng thái cache đúng, giữ thông tin cần đối soát.

### P2 — Đánh dấu thông báo đã đọc thất bại vẫn thể hiện thành công

- Vị trí: `lib/features/notifications/controllers/notification_controller.dart:109` và `:126`.
- Đổi trạng thái/số đếm trước request rồi nuốt lỗi; không rollback, không báo chưa đồng bộ và không ghi lại trạng thái mới vào cache.
- Đã tái hiện API mark-read báo offline: item vẫn đã đọc, unread về 0, không có thông báo lỗi. Nhánh đánh dấu tất cả có cùng vấn đề.
- Cần phân biệt trạng thái đọc cục bộ với xác nhận server và có cơ chế đối soát/rollback rõ ràng, tránh hiển thị như thao tác server đã thành công.

### P2 — Cache chat vẫn được giữ khi server từ chối quyền

- Vị trí: `lib/features/chat/controllers/chat_detail_controller.dart:239`, `lib/features/chat/controllers/conversations_controller.dart:111`.
- Các nhánh bắt `AppFailure` chỉ lưu message, giữ dữ liệu cũ cho cả 403/404. Trong OpenAPI, lịch sử chat có thể trả 403 khi không còn quyền truy cập.
- Cần phân biệt mất mạng/timeout/5xx với bị thu hồi quyền, loại nội dung và bản cache tương ứng khi có căn cứ server. Không xóa phiên chỉ vì lỗi mạng.

## Giới hạn tích hợp và phạm vi cần làm rõ

- **Push chưa hoàn thiện:** `pubspec.yaml` chưa có Firebase/messaging hay luồng nhận push Android; hàm đăng ký/hủy FID mới có định nghĩa, chưa thấy được gọi từ vòng đời app. Không đồng nhất tab lấy danh sách thông báo REST với nhận push khi app nền/tắt.
- **Âm thanh giọng nói mới là lựa chọn UI/DTO:** `PushSettingsScreen` gửi `sound_type`, nhưng schema settings hiện tại không mô tả trường này; chưa thấy file âm thanh/luồng phát hoặc thu âm tương ứng. Không coi việc chọn “Giọng nói” là đã tích hợp phát âm thanh.
- **Chat nhóm vượt phạm vi chốt:** `conversations_screen.dart:185` có nút tạo nhóm và gọi `conversations/group`, trong khi quy ước hiện tại nói không làm chat nhóm. Cần thống nhất lại phạm vi; đợt rà soát không tự xóa code thành viên khác.
- **Dữ liệu chat riêng tư:** nội dung tin nhắn được ghi qua `JsonCache`/preferences (`chat_repository.dart:275`). Hướng dẫn đã cung cấp yêu cầu không dùng cache JSON không nhạy cảm cho tin nhắn riêng tư. Cần chọn lưu trữ phù hợp và chính sách logout; namespace theo user chưa thay thế bảo vệ dữ liệu nhạy cảm.
- **Cài đặt push có thể gửi request chồng nhau:** switch chưa khóa trong lúc PUT; response và rollback có thể về khác thứ tự thao tác. Cần serialize hoặc quản lý phiên bản và đối soát khi timeout.

## Điểm đã kiểm tra ở các module còn lại

- Khung app giữ một MaterialApp, các tab/routes được gắn qua điểm nối hiện có. Auth có validate, guard request và lưu token qua hạ tầng chung; bộ test auth/core chạy đạt.
- Feed/posts có controller phân trang quản lý phiên, dispose/cancel, chống load trùng, giới hạn cache và giữ dữ liệu khi lỗi mạng. Composer có trạng thái kết quả chưa xác định và bản nháp. Điều này được xác nhận bằng đọc mã và các test hiện có, không thay nghiệm thu backend/thiết bị.
- Hồ sơ/quan hệ có lease theo tài khoản và epoch để bỏ response cũ; có xử lý cache và quyền truy cập. Ngân hàng câu hỏi có generation cho phân trang/bộ lọc, validation và luồng đối soát khi thao tác ghi chưa rõ kết quả. Các test tương ứng đã chạy đạt.
- Không phát hiện lỗi phân tích tĩnh hay test hiện có thất bại. Không suy ra các module trên không còn lỗi từ kết quả này.

## Kiểm thử tiếp trên Android thật

1. Đăng nhập → đọc bảng tin/ảnh → ngắt mạng → refresh → force-stop/mở lại; xác nhận đúng bài và tài khoản, spinner kết thúc, ảnh chưa cache có fallback.
2. Đăng bài/nộp câu hỏi/upload/chat rồi ngắt mạng giữa thao tác; kiểm tra bản nháp, kết quả thật trên server và thử lại không tạo trùng.
3. Mở/đóng chat liên tục, quay lại khi API đang tải, logout/đổi tài khoản khi socket/request còn chạy; kiểm tra số kết nối, dữ liệu và callback cũ.
4. Token hết hạn, nhiều GET đồng thời, refresh lỗi mạng so với refresh bị từ chối; xác nhận chỉ refresh một luồng và không replay thao tác ghi.
5. Đánh dấu thông báo khi offline, typing/read receipt/2 tin giống nhau; kiểm tra cả hai thiết bị và sau khi mở lại app.
6. Chặn người dùng trong lúc đang xem bài/hồ sơ/chat; xác nhận quyền và cache ở các màn liên quan được cập nhật.
7. Chọn/hủy media, từ chối quyền, font lớn, bàn phím, màn nhỏ; kiểm tra nút chính và lỗi overflow.
8. Kiểm tra APK ARM64/release trên điện thoại thật và push khi app nền/tắt sau khi có triển khai tương ứng. Debug x86_64 không thay cho bước này.

Nguồn hợp đồng: [OpenAPI của server](https://snsqb.duckdns.org/api/v1/docs/openapi.json), tải ngày 17/11/2026. Chưa dùng API ghi hay tài khoản thật để kiểm chứng backend trong đợt này. Không đổi success code đang dùng chỉ theo ví dụ `0000` của Swagger; cần giữ phân biệt với giá trị `1000` đã quan sát từ server trước đây.
