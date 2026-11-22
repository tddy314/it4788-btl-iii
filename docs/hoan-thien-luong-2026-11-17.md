# Hoàn thiện và kiểm tra luồng ngày 17/11/2026

> Bản đối chiếu tiếp theo ngày 18/11: [PDF–Swagger–code](doi-chieu-pdf-swagger-2026-11-18.md), 191 kiểm thử đạt. Các kết luận cache thông báo/ngân hàng câu hỏi, mật khẩu mới, tìm kiếm và GIF trong bản tiếp theo được ưu tiên so với mô tả trạng thái ngày 17/11 bên dưới.

Tài liệu bàn giao các bản sửa sau [đợt rà soát](kiem-tra-tich-hop-2026-11-17.md). Công việc giới hạn ở Flutter/Android và tích hợp server của thầy; không xây backend, tài khoản mới, chat nhóm hay API admin.

## Những luồng đã sửa

| Luồng | Hành vi sau sửa |
| --- | --- |
| Mở/đóng chat, logout/đổi tài khoản | Bỏ response hết hiệu lực; hủy subscription, timer, upload và đóng socket. Repository cũ không theo sang phiên khác. Tab danh sách tạm ngắt socket khi vào chi tiết để tránh hai kết nối cùng hoạt động. |
| Kết nối STOMP | Xác minh chứng chỉ WSS mặc định; timeout cả handshake; single-flight connect; xử lý heartbeat, SockJS và UNSUBSCRIBE; đóng socket đến muộn; không tự reconnect/replay thao tác ghi vô hạn. |
| Nhận sự kiện chat | Phân loại NEW_MESSAGE, typing, read receipt và thu hồi trên `/user/queue/messages`. Payload typing gửi `typing`, ID gửi số nguyên. Read receipt chỉ áp dụng đến ID được xác nhận. |
| Gửi tin | Chỉ server ID/broadcast tương ứng mới xác nhận sent. Sau timeout/mất kết nối, hiển thị chưa xác nhận; không tự gửi lại. Lưu outbox trước khi gửi; nếu lưu nháp thất bại thì không phát thao tác gửi mới. |
| Thử lại ảnh/GIF | Dùng lại bản ghi/client ID; URL đã upload được giữ. Không tạo bubble mới khi retry. Upload đã truyền dữ liệu nhưng mất phản hồi được coi là chưa rõ kết quả, không tự upload lại. |
| Tin giống nhau | Hai ID server khác nhau được giữ riêng dù nội dung và thời gian giống nhau. Chỉ đối soát theo định danh, không gộp theo nội dung trong 30 giây. |
| Cache và nháp chat | Cache riêng tư chuyển sang `DraftStore` dùng secure storage, tối đa 50 tin/record và 12 resource hội thoại; giữ trạng thái failed/unconfirmed khi phục hồi. Bản nháp có cả text và outbox, lưu ngay khi thay đổi. Có dọn cache chat plaintext cũ của tài khoản hiện tại. |
| Media chat | Kiểm tra dung lượng/chữ ký loại ảnh, sao chép tệp picker sang thư mục bền vững theo user trước khi gửi, giữ tệp còn được tham chiếu và dọn tệp mồ côi. |
| Offline/quyền truy cập | Offline, lỗi server hoặc payload lỗi giữ dữ liệu đang xem. 401/403/404 loại lịch sử/cache không còn quyền; giữ nội dung do người dùng đang soạn. Không đăng xuất chỉ vì mất mạng. |
| Thông báo đã đọc | Chờ server xác nhận trước khi đổi trạng thái/số đếm; lưu cache sau thành công. Lỗi hiển thị rõ, không báo thành công giả; thao tác chưa rõ kết quả chỉ đối soát bằng GET. |
| Phân trang/thông báo | Refresh không bị response trang cũ ghi đè; chống tải chồng, trùng ID, cursor lặp; chặn số mục RAM. Có nút tải thêm và thông báo lỗi thay cho spinner vô hạn. |
| Chạm thông báo | Kiểm tra loại/ID, chỉ mở một route khi chạm liên tiếp, đi qua router bảo vệ phiên. QUESTION có fallback vào ngân hàng câu hỏi vì API hiện tại không có endpoint đọc chi tiết question độc lập theo ID; không giả mạo ID câu hỏi thành ID phiên. |
| Cài đặt push | Serialize PUT, giữ giá trị server xác nhận, khóa thao tác khi kết quả chưa rõ và đối soát bằng GET. Giữ `quiet_hours`/category không hiển thị; không gửi `sound_type` ngoài schema lên server. |
| Chặn/bỏ chặn từ hồ sơ/bạn bè | `SocialScope` truyền sự thay đổi quan hệ đến bảng tin; ẩn bài của tài khoản vừa chặn, loại khỏi cache, tải lại có kiểm soát; bỏ chặn cho tải lại mà không giữ bộ lọc xóa cũ. |
| Emote bài viết/bình luận/chat | Dùng `core/text/emote_converter.dart` chung. Chuyển ký tự emote nhưng giữ nguyên HTTP/HTTPS link; sửa lỗi converter cũ có thể đổi `:/` trong URL thành emoji. Đối soát bài/bình luận mất phản hồi dùng cùng nội dung đã chuyển emote với request, tránh gửi lại vì so sánh nhầm bản nháp với nội dung server. |
| Phạm vi | Bỏ lối tạo chat nhóm khỏi giao diện và từ chối mở nội dung GROUP theo deep link trong màn chat một-một. |

## Khi server không trả `client_msg_id`

OpenAPI mô tả chưa xác nhận hỗ trợ echo hoặc chống trùng bằng `client_msg_id`. Vì vậy client không mặc định UUID tự sinh bảo đảm idempotency backend, cũng không dùng nội dung giống nhau để tự xác nhận gửi thành công.

Nếu server không trả định danh đối soát, tin cục bộ có thể ở trạng thái “Chưa xác nhận” trong khi bản server đã xuất hiện trong lịch sử. Bấm “Kiểm tra” sẽ tải lại lịch sử; người dùng có thể giữ hoặc bỏ **bản cục bộ** sau khi đối chiếu. Thao tác này không gửi/xóa tin trên server. Đây là cách xử lý an toàn khi thiếu hợp đồng xác nhận từ backend; chưa báo là đã kiểm chứng server thật có echo ID.

## Nhận push và thu âm: vẫn là phần frontend

- `PushCoordinator` tích hợp Firebase Messaging Android, đăng ký/hủy FID qua API hiện có, nhận foreground/background và mở nội dung sau kiểm tra tài khoản/phiên. SDK được khởi tạo sau frame đầu và có giới hạn chờ; lỗi push không chặn mở app.
- Firebase Messaging **17.1.0** có `register()` và `onRegistered` trả Firebase Installation ID. Manifest bật `firebase_messaging_installation_id_enabled`. Dùng FID cho `devices/fid`, không lấy FCM registration token thay vào trường này.
- Không tạo Firebase project hoặc backend mới. Bản cài đặt cần cấu hình Firebase Android **của project tương ứng với server thầy**. Thiếu cấu hình, app vẫn chạy các luồng khác và cài đặt ghi rõ push chưa được cấu hình.
- `NotificationSoundController` thu âm tối đa 15 giây, lưu theo tài khoản, chọn mặc định/giọng nói và nghe thử. Quyền micro chỉ hỏi khi bấm thu âm; bản thu dùng FileProvider giới hạn ở thư mục âm thanh của app. File được dọn có giới hạn, không đưa `sound_type` vào REST DTO.
- `NotificationPresenter` áp dụng cài đặt âm thanh/rung/category và deduplicate khi app tự hiển thị thông báo. Khi không có `recipient_user_id`, chỉ hiện nội dung chung để tránh lộ nội dung của tài khoản trước.
- Backend nên gửi **data-only** để app tự áp dụng âm thanh/kiểm tra phiên cả khi chạy nền. Với notification payload, Android tự hiển thị ở nền; client không render lần hai. Không thể bảo đảm âm thanh tùy chọn hay lọc nội dung trước khi hệ điều hành hiển thị payload loại này chỉ bằng code Flutter. Cần kiểm chứng payload thực tế với server.
- Chưa có cấu hình Firebase phù hợp nên **chưa nghiệm thu push từ server thật**, không dùng test console hay dữ liệu giả làm bằng chứng đã tích hợp thật.

### Cấu hình bản Android có nhận push

Application ID hiện tại: `com.example.it4788_btl`. Xin bộ cấu hình **client Android** đúng project/package từ phía phụ trách server, không xin service account hay khóa quản trị. Điền bản sao local của [template](firebase.android.example.json), rồi chạy:

```sh
flutter run --dart-define-from-file=docs/firebase.android.local.json
```

Bốn trường là cấu hình client Firebase, không phải mật khẩu/tokens người dùng. Không thêm credential backend vào file này. Bản local được gitignore. Không điền cấu hình của một project không liên quan rồi kết luận push của server thầy sẽ hoạt động.

Payload data client có thể đọc gồm `recipient_user_id`, `category`, `title`, `body`, `target_type`, `target_id`; hoặc `target` là object/JSON gồm `type`, `target_id`. Không tự yêu cầu thay backend trong đợt sửa này; cần đối chiếu payload thật khi cấu hình được cung cấp.

## Các điểm nối dùng chung

- `SqbApp.navigatorKey` là tham số tùy chọn, giữ tương thích các caller hiện có; key được thay khi đổi tài khoản để không tái sử dụng stack cũ. Vẫn chỉ có một MaterialApp.
- `AuthController.beforeLogout` là callback tùy chọn để hủy nhận push trước logout. Lỗi hủy push không ngăn logout cục bộ.
- `AuthApplication` ghép `PushScope` và `SocialScope` qua dependency hiện có. Không thêm HTTP client/token store hay quản lý trạng thái thứ hai.
- Android compile SDK 37 để đáp ứng plugin thông báo; bật core-library desugaring, thêm POST_NOTIFICATIONS/RECORD_AUDIO, icon thông báo và FileProvider. Giữ `shared_preferences_android` 2.5.4 theo bản sửa R8/JNI trước đây.

## Kiểm chứng

Các kiểm thử hiện có và mới bao phủ auth, router, phân trang/cache, draft, media validation, quyền, ngân hàng câu hỏi, quan hệ, post notification, giao thức STOMP, lỗi bộ nhớ và phản hồi đến muộn. **176 test đạt**, `flutter analyze --no-pub` không có lỗi. Có kiểm tra thêm mất quyền khi tải trang tiếp theo ở chat/thông báo/ngân hàng câu hỏi, lưu phần lịch sử đã tải thêm vào cache có giới hạn, giới hạn tin nhắn RAM và đối soát bài/bình luận có emote sau timeout mà không gửi lại. Các test giả không thay cho nghiệm thu trên điện thoại thật.

- Build debug x86_64 và release ARM64 thành công; release khoảng **22,2 MB**. Bản release vẫn dùng cấu hình ký debug của dự án cho mục đích bài tập, chưa cấu hình phát hành lên cửa hàng.
- Đã cài debug lên emulator Android API 37, mở được màn đăng nhập, kiểm tra nhập rỗng hiện hai lỗi tiếng Việt. Đã tắt Wi-Fi/dữ liệu trên emulator, force-stop/mở lại: vẫn hiện màn đăng nhập và banner offline, không vào nội dung bảo vệ. Đã khôi phục hai kết nối về trạng thái ban đầu. Lần mở offline có `am start -W` báo timeout khi máy đang build release; ảnh/UI dump sau đó xác nhận giao diện đã hiện, chưa kết luận hiệu năng khởi động trên điện thoại thật.
- Ảnh/log cục bộ trong `.dart_tool/fix-*`, `.dart_tool/final-*`, `.dart_tool/handoff-*` và `.dart_tool/review-*`. Không lưu mật khẩu/token thực tế trong tài liệu, fixture hay Git; không dùng API ghi nghiệp vụ hoặc gửi tin thật tới người khác trong đợt này.
- Chưa nghiệm thu API nghiệp vụ trên server thật ở bản sửa này, cache feed sau đăng nhập trên thiết bị thật, native thu/phát giọng nói hoặc push từ server. Cấu hình Firebase còn thiếu; backend echo `client_msg_id`, payload push và data-only/notification cần đối chiếu thực tế khi có môi trường phù hợp.

Nguồn: [OpenAPI của thầy](https://snsqb.duckdns.org/api/v1/docs/openapi.json), [Firebase Messaging/FID](https://firebase.google.com/docs/cloud-messaging/flutter/get-started), [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications), [record](https://pub.dev/packages/record). Đối chiếu ngày 17/11/2026; thông tin payload/server chưa kiểm chứng đã được ghi riêng ở trên.
