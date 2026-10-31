# Context cho AI làm việc trong dự án SQB

Đọc file này trước khi code. Hướng dẫn áp dụng cho toàn repository. Đây là quyết định và quy ước dự án; yêu cầu mới, rõ ràng của người dùng có thể cập nhật chúng. Kiểm tra code thực tế trước khi sửa vì hiện trạng có thể thay đổi sau mỗi lần merge.

## 1. Phạm vi đã chốt với nhóm

- Bài tập lớn IT4788: mạng xã hội cho sinh viên đóng góp câu hỏi vào ngân hàng đề theo môn học; trải nghiệm giao diện giống Facebook.
- Flutter, chỉ triển khai Android mobile, giao diện và thông báo cho người dùng bằng tiếng Việt.
- Nhóm làm frontend và tích hợp server của thầy; không triển khai backend, database, thuật toán AI hay trang admin.
- **Thầy cấp tài khoản: không làm đăng ký hoặc OTP kích hoạt từ đăng ký.** Đổi mật khẩu sau đăng nhập là chức năng riêng.
- **Phải đăng nhập trước khi vào bảng tin, xem bài và tương tác. Không có chế độ khách.** Đề xuất cho khách xem bài đã được hủy sau khi xác nhận API đọc bài cần token.
- Khi còn phiên đăng nhập, mất mạng không đồng nghĩa với đăng xuất; có thể xem nội dung đã lưu trên máy.
- Luồng chính: đăng nhập → chọn môn đang học → soạn/nộp bộ câu hỏi → theo dõi đề xuất; bổ sung các tính năng xã hội theo công việc được giao.
- Chỉ triển khai tính năng được giao. Không tự mở rộng sang minigame, AI, chat nhóm, duyệt câu hỏi hay sinh đề cho giảng viên.

## 2. Mất mạng là tiêu chí nghiệm thu bắt buộc

**Thầy sẽ ngắt kết nối mạng trong lúc kiểm tra bài tập lớn**, quan sát việc gọi API, nội dung bài viết còn hiển thị và cách app xử lý tình huống vận hành. Mỗi feature phải xử lý cả luồng lỗi.

1. Bảng tin giữ bài đã cache khi offline hoặc refresh thất bại; không xóa nội dung cũ để hiện trang lỗi toàn màn hình. Ảnh chưa được lưu cần fallback, không giả vờ đã có dữ liệu.
2. Validate input trước khi kiểm tra mạng/gửi request. Có Wi-Fi/mobile chưa chắc có Internet; vẫn bắt lỗi từng request.
3. Không báo thành công khi server chưa xác nhận, không loading vô hạn, không retry/polling liên tục.
4. Ngắt mạng giữa upload/đăng bài/gửi câu hỏi/chat phải giữ nội dung đang soạn và thể hiện trạng thái gửi đúng.
5. Timeout có thể xảy ra sau khi server đã xử lý. **Không tự replay POST/PUT/PATCH/DELETE hoặc upload**; kiểm tra kết quả trước khi cho gửi lại để tránh trùng.
6. Khi mạng trở lại, refresh/đồng bộ có kiểm soát; tránh trùng bài/tin nhắn và request đồng thời không cần thiết.
7. Không xóa phiên chỉ vì offline/timeout/lỗi server. Phân biệt lỗi mạng với token bị server từ chối, quyền truy cập bị thu hồi và nội dung đã xóa.
8. Cache/bản nháp phải tách theo tài khoản, không lộ dữ liệu user cũ sau logout hoặc đổi tài khoản. Dispose controller/subscription và bỏ response cũ khi màn hình/phiên không còn phù hợp.
9. Xử lý thêm lỗi server, JSON sai/rỗng, hết trang, quyền thiết bị bị từ chối, token hết hạn, app chạy nền và đóng/mở lại.
10. Kiểm thử trên điện thoại thật các bước ngắt mạng trước/trong thao tác và khôi phục mạng. Mock/unit test không thay cho nghiệm thu này.

### Các tình huống kiểm thử mở rộng cần dự kiến

Danh sách dưới đây do nhóm chủ động dự kiến theo yêu cầu người dùng, **không phải danh sách thầy đã công bố và không có nghĩa các tình huống đã được xử lý trong code**. Khi triển khai feature, chọn các trường hợp liên quan để thiết kế, kiểm thử và ghi nhận kết quả. Không tự xây feature ngoài phạm vi chỉ để đáp ứng một trường hợp chưa áp dụng.

| Nhóm | Thao tác/tình huống có thể được kiểm tra | Hành vi cần hướng tới |
| --- | --- | --- |
| Mạng | Mở app lần đầu khi offline, chưa có phiên/cache | Không vào bảng tin trái phép, không giả dữ liệu; thông báo phù hợp, cho thử lại khi có mạng |
| Mạng | Mở lại app offline khi đã có phiên và bài lưu trên đĩa | Khôi phục phiên/cache đúng tài khoản; không bắt buộc gọi server thành công mới hiện nội dung đã lưu |
| Mạng | Có Wi-Fi nhưng router mất Internet, DNS lỗi hoặc mạng cần đăng nhập | Request kết thúc bằng lỗi/timeout phù hợp; không coi biểu tượng Wi-Fi là bằng chứng gọi API được |
| Mạng | Bật chế độ máy bay, đổi Wi-Fi ↔ 4G, ngắt/nối liên tục khi đang tải | Không crash, không treo spinner, không tạo chuỗi retry/subscription vô hạn; cho phục hồi có kiểm soát |
| Mạng | Server nhận thao tác nhưng response bị mất; người dùng bấm thử lại | Không kết luận thao tác chưa xảy ra; kiểm tra trạng thái trước khi gửi lại, tránh tạo trùng |
| Phiên | Sai tài khoản/mật khẩu, tài khoản bị khóa hoặc server từ chối phiên | Lỗi tiếng Việt rõ ràng; không mở nội dung bảo vệ hoặc báo thành công giả |
| Phiên | Access token hết hạn khi nhiều API đang chạy | Gom refresh, không vòng lặp 401; kết quả đồng bộ, không tự replay thao tác ghi |
| Phiên | Refresh token hết hạn/thu hồi so với refresh thất bại do mất mạng | Chỉ xử lý hết phiên khi có căn cứ xác thực; lỗi mạng giữ phiên/cache theo quy tắc offline |
| Phiên | Logout rồi Back; logout hoặc đổi A → B khi request A chưa trả về | Không quay lại màn/nội dung của A, không ghi response/token đến muộn vào phiên B |
| Phiên | Logout lúc offline hoặc khi API logout lỗi | Xử lý phiên/dữ liệu cục bộ rõ ràng; không tuyên bố server đã thu hồi phiên nếu chưa xác nhận |
| Phiên | Cùng tài khoản trên hai máy, đổi mật khẩu/thu hồi phiên ở máy kia | Phản ánh kết quả server theo chính sách phiên thực tế; không tự giả định server chỉ cho một thiết bị |
| Vòng đời | Home/khóa máy/chuyển app khi đang soạn, upload, gọi API hoặc chat | Giữ trạng thái/draft phù hợp, không tiếp tục cập nhật widget đã dispose; kiểm tra lại khi foreground |
| Vòng đời | Android hủy process rồi mở lại app | Khôi phục phần đã lưu bền vững; không hứa phục hồi nội dung chỉ tồn tại trong RAM hoặc file tạm |
| Điều hướng | Back, đổi tab, mở/đóng màn liên tục lúc request đang chạy | Không `setState` sau dispose, không listener/socket trùng, không request vô ích do build lại |
| Thao tác | Bấm Gửi/Lưu/Xóa nhiều lần hoặc bấm nhanh Like rồi Unlike | Chặn gửi lặp; số đếm và trạng thái cuối khớp server; optimistic update phải rollback/đối soát khi lỗi |
| Bảng tin | Refresh/tải thêm khi offline, kéo tải liên tục hoặc đã hết trang | Giữ bài hiện có, dừng loading; không gọi lại cùng trang vô hạn, không trùng/mất bài hoặc nhảy vị trí vô cớ |
| Bảng tin | Refresh và load-more chồng nhau; response trang cũ về sau trang mới | Không ghi đè danh sách mới bằng dữ liệu cũ; quản lý thứ tự request và cursor |
| Dữ liệu thay đổi | Bài/câu hỏi/người dùng đã bị xóa hoặc đổi quyền khi đang mở | Xử lý 403/404 đúng, không tiếp tục hiển thị cache như thể vẫn có quyền; không crash khi trở về danh sách |
| Tìm kiếm | Gõ nhanh, xóa từ khóa hoặc đổi bộ lọc trong khi kết quả cũ chưa về | Chỉ hiện kết quả cho truy vấn hiện tại; debounce/hủy hoặc bỏ response cũ; có trạng thái rỗng |
| Đầu vào | Rỗng, chỉ dấu cách/xuống dòng, tiếng Việt, emoji, dán văn bản dài | Validate nhất quán, không cắt hỏng ký tự; giữ nội dung nhập khi lỗi và không trim mật khẩu tùy tiện |
| Giá trị biên | Nội dung 499/500/501 từ; media ngay dưới/đúng/vượt giới hạn | Kiểm tra đúng đơn vị từ/byte/thời lượng đã chốt; thông báo cụ thể, không nhầm từ thành ký tự |
| Media | Tệp rỗng/hỏng, ảnh dung lượng lớn, sai loại hoặc đổi đuôi file | Không chỉ tin phần mở rộng; từ chối hoặc xử lý lỗi an toàn, không crash khi decode/xem trước |
| Media | Chọn ảnh thứ 5, trộn ảnh/video, video ngắn hơn 1 giây hoặc dài hơn 10 giây | Áp dụng giới hạn nghiệp vụ; sửa lựa chọn được mà không làm mất toàn bộ nội dung đang soạn |
| Media/quyền | Hủy picker/camera, từ chối quyền, từ chối vĩnh viễn hoặc thu hồi quyền trong Settings | Quay lại ổn định, giữ draft, giải thích và hướng dẫn cấp quyền khi cần; không hỏi quyền lặp liên tục |
| Media/upload | Một trong nhiều ảnh upload lỗi; hủy/rời màn giữa upload; URL hết hạn | Không tạo bài thiếu ảnh ngoài ý muốn, giữ trạng thái từng tệp; thử lại không upload/gửi toàn bộ một cách mù quáng |
| Cache/bộ nhớ | Cache JSON hỏng, cache ảnh bị dọn, file nháp bị xóa, hết dung lượng hoặc storage lỗi | Có fallback và thông báo thích hợp; lỗi cache không biến API thành công thành thất bại; không xóa toàn bộ dữ liệu để chữa lỗi |
| API | HTTP 200 nhưng code nghiệp vụ lỗi; 400/401/403/404/413/429/5xx | Phân loại đúng, dừng loading, giữ input phù hợp; không retry mọi lỗi hoặc hiện nguyên exception/token cho người dùng |
| API | Body HTML/rỗng/JSON hỏng, thiếu trường, null, sai kiểu, enum lạ | Không crash; báo dữ liệu không hợp lệ hoặc fallback cho trường không bắt buộc, không tự bịa kết quả |
| Câu hỏi | Không có môn đang học, danh sách đề xuất/câu hỏi rỗng | Hiện empty state và hướng dẫn phù hợp; không tự gán môn hoặc gọi API admin |
| Câu hỏi | Phiên chuyển từ PENDING sang REVIEWING/RESOLVED lúc sinh viên đang sửa/xóa | Xử lý từ chối của server và cập nhật quyền; giữ phần nhập để người dùng xem lại, không ép sửa phiên đã khóa |
| Câu hỏi | Phiên chỉ duyệt một phần, hoặc câu hỏi đổi phiên bản khi người khác đang trả lời | Hiện đúng kết quả từng cấp; không gắn “đã duyệt tất cả”; xử lý dữ liệu cũ theo API, không chấm bằng đáp án cache |
| Câu hỏi | Chưa chọn đáp án, đáp án ẩn, đánh giá 0 hoặc 4, rating ngoài khoảng | Theo schema/validation; 0 là giá trị hợp lệ, không dùng kiểm tra truthy để loại 0; không làm lộ đáp án chưa được phép |
| Quan hệ | Hai máy cùng gửi/chấp nhận lời mời; một phía hủy hoặc chặn trong lúc thao tác | Không nhân đôi quan hệ; cập nhật trạng thái từ server, xử lý “đã thực hiện” và yêu cầu không còn tồn tại |
| Chặn | A chặn B khi B đang xem hồ sơ/bài hoặc đang chat; sau đó bỏ chặn | Phản ánh quyền mới ở các màn liên quan, ngăn thao tác bị cấm; không mặc định bỏ chặn tự khôi phục bạn bè |
| Chat | Mất mạng khi gửi, reconnect nhận lại cùng tin, lịch sử trùng sự kiện socket | Phân biệt đang gửi/thất bại/đã xác nhận; đối soát theo ID server, không nhân đôi hoặc tự đổi thứ tự sai |
| Chat | Vào/ra hội thoại liên tục, app nền rồi trở lại, token socket hết hạn | Không mở nhiều kết nối/subscription trùng; khôi phục lịch sử và trạng thái đọc/đang nhập hợp lý |
| Thông báo | Bấm nhiều lần, app đang tắt/nền, đã logout hoặc nội dung đích đã bị xóa | Qua kiểm tra phiên/quyền, điều hướng đúng một lần; có fallback cho nội dung không còn tồn tại |
| Giao diện | Máy màn nhỏ, font hệ thống lớn, bàn phím mở, nội dung/tên rất dài | Không overflow hoặc che nút chính; cuộn được, giữ safe area và khả năng đọc/thao tác |
| Hiệu năng | Cuộn nhiều bài/ảnh, đổi tab và mở media nhiều lần | Không tải tất cả vô hạn, không phình RAM/cache hoặc rò listener; trạng thái danh sách còn nhất quán |

**Cách dùng danh sách:** với feature được giao, chuẩn bị điều kiện ban đầu → thao tác gây lỗi/thay đổi → kết quả mong đợi → phục hồi và thử lại. Kết hợp nhiều yếu tố, ví dụ token hết hạn đúng lúc đổi mạng, hoặc logout trong khi upload còn chạy. Kiểm tra lại cả UI, số request và dữ liệu thực tế trên server khi có môi trường thử phù hợp; đừng chỉ kiểm tra snackbar đã hiện.

Thử nghiệm lỗi server/schema, race condition hoặc hết phiên nên dùng fake/mock hay môi trường test có kiểm soát. Không tự phá dữ liệu, spam request, thay cấu hình thiết bị/server hoặc dùng API admin để tạo tình huống trên hệ thống dùng chung. Chỉ ghi “đã kiểm thử” khi thực sự chạy; nếu phụ thuộc backend chưa hỗ trợ thì ghi rõ giới hạn, không giả lập thành hành vi đã tích hợp.

## 3. Hiện trạng — cập nhật 31/10/2026

Đã có khung app/core và triển khai mục 1 trong `features/auth`, `features/settings`: màn đăng nhập qua API, lưu phiên, callback refresh, đăng xuất cục bộ/server và đổi mật khẩu. `main.dart` gắn `AuthApplication` vào khung qua builders/routes công khai; không thay implementation của app/core. Tab Cá nhân tạm hiển thị menu cài đặt tài khoản, chưa phải hồ sơ. Những feature khác vẫn giữ `.gitkeep`; **chưa có homepage nghiệp vụ, feed cache tích hợp hay chat**.

Đã đối chiếu Swagger ngày 31/10/2026, chạy `flutter analyze --no-pub` sạch lỗi và 31 kiểm thử đạt. Đã cài lại NDK, bổ sung SDK/CMake và build APK debug x86_64 thành công; đã đăng nhập với server thật bằng tài khoản người dùng cung cấp trên emulator Android API 37, kiểm tra vào khung 5 tab. `android/gradle.properties` đặt `kotlin.incremental=false` để tránh lỗi cache khi project ở D: và Pub cache ở C:. Chưa xác nhận ARM64, thiết bị thật hoặc refresh/logout/đổi mật khẩu trên server thật. Không suy ra toàn bộ tính năng đã tích hợp từ test giả hoặc một lần login thật. Xem [hướng dẫn mục 1](docs/muc-1-auth-settings.md) để gắn các feature còn lại.

## 4. Thành phần có sẵn — tái sử dụng trước khi tạo mới

| Vị trí | Thành phần và mục đích |
| --- | --- |
| `lib/main.dart` | `AppBootstrap`: khởi tạo dependency, loading/thử lại khi lỗi |
| `lib/app/app.dart` | `SqbApp`: locale vi, lifecycle, điểm gắn màn hình |
| `lib/app/app_dependencies.dart`, `app_scope.dart` | `AppDependencies`, `AppScope.of(context)` cung cấp service dùng chung |
| `lib/app/router/app_router.dart` | `AppRoutes`, `AppRouter`: bảo vệ route bằng phiên, màn chưa tìm thấy |
| `lib/app/app_shell.dart` | `AppShell`, `AppTab`: feed, questionBank, friends, notifications, profile; chỉ khởi tạo tab khi được mở |
| `lib/app/theme/` | `AppColors`, `AppTheme`: màu tập trung, theme Material tiếng Việt |
| `lib/core/config/app_config.dart` | `AppConfig`: HTTPS base URL, timeout, success code qua dart-define |
| `lib/core/network/api_client.dart` | `ApiClient`: get/request, Bearer token, envelope, lỗi, cancel/progress, điểm nối refresh token |
| `lib/core/network/connection_monitor.dart` | `ConnectionMonitor`, `DeviceConnectionMonitor`, `ConnectionStatus`: unknown/offline/available |
| `lib/core/errors/app_failure.dart` | `AppFailure`, `FailureKind`, `canUseCache`: lỗi thống nhất để UI xử lý |
| `lib/core/storage/key_value_store.dart` | `KeyValueStore`, secure storage và preferences adapters |
| `lib/core/storage/session_store.dart` | `SessionStore`, `SessionTokens`: restore/save/clear phiên, lưu token bảo mật |
| `lib/core/storage/json_cache.dart` | `JsonCache`, `CacheEntry`: cache nhỏ theo user/resource, có thời điểm lưu |
| `lib/core/storage/cached_resource_controller.dart` | `CachedResourceController<T>`: cache-first, giữ dữ liệu khi lỗi mạng, chặn load trùng |
| `lib/core/storage/draft_store.dart` | `DraftStore`: bản nháp JSON theo user/name, dùng secure storage |
| `lib/core/media/media_upload_service.dart` | `MediaUploadService`, `MediaPurpose`, `UploadedMedia`: upload multipart, kiểm tra dung lượng, progress/cancel |
| `lib/core/widgets/` | `AppButton`, `AppTextField`, loading/empty/error, `ConnectionBanner`, `AppNetworkImage`, `AppAvatar`, `CachedResourceView<T>` |
| `lib/core/validation/validators.dart` | `Validators`: bắt buộc, đếm từ, giới hạn số từ |
| `test/support/fakes.dart` | `MemoryStore`, `FakeConnection`: test không phụ thuộc plugin thật |
| `lib/features/auth/` | `AuthApplication`, `AuthController`, `AuthRepository`, `DeviceIdentity`, `LoginScreen`, `AuthValidation`: xác thực qua core và UUID cài đặt bền vững |
| `lib/features/settings/` | `SettingsScreen`, `SettingsRoutes`, `ChangePasswordScreen`: menu tài khoản, đổi mật khẩu, đăng xuất và đóng app |

Dependencies đã có: Flutter localizations, Dio, flutter_secure_storage, shared_preferences, connectivity_plus, cached_network_image. Đọc `pubspec.yaml`/lock để biết phiên bản; không tự thêm một HTTP client, storage hoặc giải pháp quản lý trạng thái thứ hai cho cùng mục đích.

## 5. Quy tắc tích hợp feature

- UI lấy service qua `AppScope.of(context)`, truyền dependency vào controller/repository. Không gọi HTTP trực tiếp từ widget hoặc tạo token store riêng.
- `SqbApp` nhận `loginBuilder`, `tabBuilders: Map<AppTab, WidgetBuilder>` và `protectedRoutes: Map<String, WidgetBuilder>`. Gắn màn vào đây; giữ một `MaterialApp` và cơ chế router chung.
- Auth gọi login với `authenticated: false`, map user ID thành chuỗi trong `SessionTokens`, rồi `await session.save(tokens)`. `session.clear()` bỏ stack điều hướng của user cũ.
- `AuthApplication` đã gắn `ApiClient.refreshTokens` vào `AuthController.refresh`. Callback dùng API refresh với `authenticated: false`, trả cặp token mới cùng user ID; **không tự save token trong callback**. Client gom refresh đồng thời, save token và chỉ retry GET/HEAD một lần. Server từ chối refresh bằng lỗi xác thực/quyền thì auth xóa đúng phiên cũ; lỗi mạng giữ phiên. Chưa kiểm chứng refresh bằng tài khoản/server thật.
- Client nhận đường dẫn tương đối sau base URL, ví dụ `posts`, không gắn thêm `/api/v1` và không truyền URL domain khác. `decode` nhận payload `data`, không phải toàn response.
- Request của client cần envelope JSON; tải file binary hoặc upload presigned cần đường xử lý riêng phù hợp, không gửi Bearer token sang domain khác.
- `MediaUploadService` chỉ upload file; feature vẫn phải chọn/chụp media, kiểm tra loại/thời lượng/số lượng và tạo DTO nghiệp vụ từ kết quả upload.
- Dùng `AppColors`/theme và widget chung. Không tạo màu, thông báo lỗi hoặc loading riêng rải rác nếu core đã đáp ứng.
- Không áp đặt thêm nhiều tầng kiến trúc cho mọi tính năng. Đặt code riêng trong feature; việc đưa thành phần mới vào core là nhiệm vụ dùng chung riêng, không tự thực hiện trong lúc làm feature.

### Bảo vệ phần dùng chung

- **Ưu tiên tái sử dụng; nếu thành phần có sẵn không đáp ứng thì tự viết widget/helper/adapter hoặc logic riêng trong feature đang phụ trách. Không sửa phần dùng chung để ép nó phục vụ feature của mình.** Có thể bọc hoặc kết hợp thành phần hiện có qua API công khai.
- Khi làm feature, không tự thay đổi implementation, chữ ký hàm, giá trị mặc định hoặc hành vi của `lib/core`, khung `lib/app`, theme hay dependency chung. Không sửa kiểm thử chung để hợp thức hóa thay đổi riêng của feature.
- Chỉ sửa phần dùng chung khi người dùng giao rõ nhiệm vụ đó. Nếu phát hiện hạn chế/lỗi của core trong lúc làm feature, ghi rõ vấn đề và giới hạn trong bàn giao; không âm thầm sửa. Phần riêng vẫn phải tuân thủ quy tắc token, quyền, lỗi và offline của dự án.
- Dùng các điểm nối đã có như builder, route registration và dependency injection để tích hợp. Không thay kiến trúc app, tạo thêm `MaterialApp` hoặc viết lại hạ tầng chung chỉ vì một màn hình cần khác biệt.

### Giao diện đồng nhất giữa các thành phần

- **Màn hình và widget mới phải thống nhất với giao diện hiện có**, kể cả khi phải tự viết phần riêng. Tái sử dụng `AppTheme`, `AppColors` và text style từ `Theme.of(context)`; không tạo theme/bảng màu riêng cho từng feature.
- Giữ nhất quán kiểu chữ, cỡ chữ theo vai trò, khoảng cách, bo góc, kích thước nút/ô nhập/avatar, icon và cách bố trí AppBar/điều hướng. Trước khi dựng màn hình, đối chiếu component và màn đã có thay vì tự thiết kế lại.
- Các trạng thái loading, rỗng, lỗi, offline, disabled và đang gửi phải có cách trình bày và thông báo tiếng Việt nhất quán; ưu tiên widget chung. Thành phần tự viết cần khớp các quy ước này.
- Dùng cùng thuật ngữ cho cùng thao tác, ví dụ “Thích”, “Bình luận”, “Thử lại”; không trộn tiếng Anh hoặc đổi nhãn tùy từng màn. Giữ cách hiển thị số đếm, thời gian và trạng thái tương đồng.
- Khi chưa có mẫu cho một thành phần, chọn cách thể hiện phù hợp với theme hiện tại và ghi nhận lựa chọn để thành viên khác dùng theo; không tự sửa theme chung. Kiểm tra cả màn nhỏ, font lớn và bàn phím mở để sự đồng nhất vẫn dùng được trên thiết bị thật.

### Cache và bản nháp

- `dependencies.cache` dùng preferences cho JSON **không nhạy cảm**, mặc định tối đa 512 KiB/record; feature phải giới hạn số bài lưu. Không lưu token, tin nhắn riêng tư hoặc cache toàn lịch sử vô hạn vào đây.
- `CachedResourceController<T>` cần userId/resource, fetch và encode/decode. Feature gọi `load()` lúc khởi tạo/refresh, dispose khi đổi màn/phiên, tự xử lý phân trang và ghép bản ghi. `CachedResourceView` không tự khởi chạy load.
- `AppNetworkImage` cache ảnh trên đĩa theo cơ chế thư viện. Chỉ ảnh đã lưu thành công có thể xem offline; cache có thể bị dọn. Chưa có đảm bảo video offline.
- `dependencies.drafts` dùng secure storage. Feature phải chủ động save/read/remove, giữ draft khi lỗi và chỉ xóa sau khi thao tác được xác nhận. File tạm cần được sao chép sang nơi bền vững nếu muốn khôi phục media sau khi mở lại app.

## 6. Hợp đồng nghiệp vụ và API cần nhớ

- **Bắt buộc đọc kỹ Swagger của từng endpoint trước khi code hoặc sửa tích hợp API.** Kiểm tra method/path, header/token, quyền, nền tảng, content type, tham số bắt buộc/tùy chọn, kiểu dữ liệu, enum, nullability, phân trang và response thành công/thất bại; không chỉ sao chép JSON ví dụ hoặc suy đoán theo tên API.
- Phân biệt schema/mô tả với ví dụ minh họa. Đối chiếu response thật trong môi trường và phạm vi được phép thử, nhất là HTTP status, `code`, payload `data`, token/cookie và khác biệt WEB/ANDROID. Nếu chưa thể kiểm chứng thì ghi rõ giả định, không báo là đã tích hợp thành công.
- Khi Swagger và server không khớp, ghi lại khác biệt đã quan sát (không lưu mật khẩu/token), cập nhật mapping/cấu hình và test hồi quy theo hợp đồng đã xác nhận; không bỏ kiểm tra lỗi hoặc mặc định mọi HTTP 200 đều thành công. Test giả phải phản ánh response thực tế đã biết, không chỉ xác nhận giả định do người code tự đặt ra.
- [Swagger](https://snsqb.duckdns.org/api/v1/swagger-ui/index.html), [OpenAPI JSON](https://snsqb.duckdns.org/api/v1/docs/openapi.json). Đọc lại phần endpoint/schema liên quan khi tích hợp; tài liệu có thể thay đổi. **Không gọi API admin từ app**.
- Base URL mặc định: `https://snsqb.duckdns.org/api/v1/`. Mã thành công mặc định đã sửa thành **`1000`** theo response login thật ngày 31/10/2026; Swagger minh họa `0000` không khớp server hiện tại. HTTP 200 chưa đủ để kết luận nghiệp vụ thành công. Đã xác nhận login payload ANDROID trả cả access/refresh token; payload WEB có thể trả refresh token null, không áp kết luận đó cho Android. Không lưu tài khoản thử hoặc token vào repo.
- API bảng tin và chi tiết bài đã được thử không token và trả HTTP 401/code 9998. Public visibility không đồng nghĩa với truy cập ẩn danh.
- PDF yêu cầu bài viết/bình luận tối đa **500 từ**, bài public, một loại Like, tối đa **4 ảnh hoặc 1 video**, không trộn ảnh/video. Ảnh tối đa 4 MB; video tối đa 10 MB và 1–10 giây. Không tự mở thêm reaction/privacy vì Swagger hỗ trợ nhiều hơn.
- Không tự thêm share, tag, nhóm xã hội, chat nhóm, sửa bình luận hay tự xóa tài khoản chỉ vì giống Facebook hoặc vì có API; xem phạm vi đã chốt cho từng chức năng.
- Nộp bộ câu hỏi hiện dùng JSON + ảnh upload, chưa xác nhận luồng nhập ZIP. Theo schema từng endpoint: tạo dùng `llm_generated`, sửa dùng `source`; ảnh gửi `media_urls` nhưng đọc có thể `image_urls`; tự tin `confidence`/`confidence_score`.
- Phân biệt phiên đề xuất với phiên đăng nhập. Phiên có `PENDING`/`REVIEWING`/`RESOLVED`; **RESOLVED không có nghĩa mọi câu được duyệt**. Sửa/xóa phiên chỉ khi server cho phép, hiện mô tả là PENDING.
- Thang đánh giá câu hỏi **0–4**, không phải 1–5. Không suy đáp án đúng khi server ẩn trường `is_correct`; lấy kết quả từ server.
- Phân trang phổ biến `after`, `limit`, `pagination.has_next`, nhưng search có thể dùng offset. Không giả định mọi endpoint giống nhau.
- Nguồn tự làm/AI phải ẩn với giảng viên theo PDF; UI tuân theo vai trò, backend phải thực thi quyền. Không rò rỉ thông tin này qua card công khai.
- Chat STOMP, push/Firebase, FID so với FCM token và dữ liệu duyệt cần kiểm chứng khi làm feature; chưa phải service đã hoàn thiện trong core.

## 7. Ranh giới công việc của 5 thành viên

| Thành viên | Phạm vi chủ trì |
| --- | --- |
| 1 | `app`, `core`, `features/auth`, ghép menu settings, cấu hình Android và tích hợp |
| 2 | `features/feed`, `features/posts`; media picker/viewer và bình luận dùng chung |
| 3 | `features/question_bank` |
| 4 | `features/profile`, `features/relationships`, `features/search`; danh sách chặn trong settings |
| 5 | `features/chat`, `features/notifications`; cài đặt thông báo trong settings |

Đây là phân công tham khảo đã thống nhất, không cấm nhiệm vụ mới do người dùng giao. Khi được giao rõ nhiệm vụ sửa API chung, router, dependency hoặc Android config, giữ tương thích với các feature khác và ghi rõ thay đổi tích hợp. Trong nhiệm vụ feature thông thường, tuân thủ mục “Bảo vệ phần dùng chung”. Không sửa/xóa công việc đang có của thành viên khác ngoài phạm vi nhiệm vụ.

## 8. Kiểm tra và bàn giao

```sh
flutter pub get
dart format lib test
flutter analyze
flutter test
```

- Chạy kiểm tra phù hợp với phần đã thay đổi. Thêm test có ích cho validation/DTO/logic phức tạp, cache, session, retry; không viết test chỉ sao chép implementation hoặc UI tĩnh.
- Không đưa password/token vào source, log, fixture, dart-define hoặc Git. Không tự tạo tài khoản, dữ liệu hay thay đổi server để thử nếu chưa có yêu cầu phù hợp.
- Kết quả bàn giao phải nêu đã làm gì, thành phần dùng lại, kiểm tra đã chạy và phần chưa xác nhận. Dữ liệu giả/placeholder không được báo thành tích hợp thật.
- Cập nhật file này khi quyết định phạm vi, API chung hoặc hiện trạng thay đổi đáng kể. Ghi trạng thái thực tế, không chép lịch sử hội thoại dài hoặc biến giả định thành yêu cầu đã chốt.

Đọc thêm: [hướng dẫn khung app](docs/khung-app.md), [phân tích yêu cầu](docs/phan-tich-yeu-cau-frontend.md), PDF trong `docs/`. File phân công cá nhân `docs/phan-cong-nhom.md` đang bị `.gitignore` bỏ qua; không dựa riêng vào file đó làm context cho người clone repository.
