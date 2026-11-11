# Context cho AI làm việc trong dự án SQB
> Đọc file này trước khi code. Hướng dẫn áp dụng cho toàn repository và từng nhánh feature. Đây là quyết định, quy ước và đặc tả kỹ thuật đã chốt của dự án; yêu cầu mới, rõ ràng của người dùng có thể cập nhật chúng. Kiểm tra code thực tế trước khi sửa vì hiện trạng có thể thay đổi sau mỗi lần merge.

---

## 1. Phạm vi đã chốt với nhóm

- **Bài tập lớn IT4788:** Mạng xã hội cho sinh viên đóng góp câu hỏi vào ngân hàng đề theo môn học; trải nghiệm giao diện và tương tác quen thuộc tương tự Facebook.
- **Nền tảng & Ngôn ngữ:** Flutter, chỉ triển khai Android mobile, toàn bộ giao diện và thông báo người dùng bằng **tiếng Việt**.
- **Phạm vi kỹ thuật:** Nhóm chỉ làm **Frontend** và tích hợp vào hệ thống Backend có sẵn do thầy giáo cung cấp; không triển khai backend, database, thuật toán AI hay trang admin.
- **Tài khoản:** **Thầy cấp tài khoản: không làm đăng ký hoặc OTP kích hoạt từ đăng ký.** Đổi mật khẩu sau đăng nhập là chức năng riêng.
- **Quyền truy cập:** **Phải đăng nhập trước khi vào bảng tin, xem bài và tương tác. Không có chế độ khách (Guest mode).** Mọi API đọc/ghi đều yêu cầu Bearer token.
- **Quản lý phiên:** Khi còn phiên đăng nhập, mất mạng không đồng nghĩa với đăng xuất; có thể xem nội dung đã lưu trên máy.
- **Luồng chính:** Đăng nhập → Chọn môn đang học → Soạn/nộp bộ câu hỏi → Theo dõi đề xuất; bổ sung các tính năng xã hội theo công việc được phân công.
- **Giới hạn nghiệp vụ:** Chỉ triển khai tính năng được giao. Không tự mở rộng sang minigame, AI, chat nhóm, duyệt câu hỏi hay sinh đề cho giảng viên.
- **Phạm vi hồ sơ và bạn bè:** Chỉ giữ tìm người trong tab Bạn bè (`GET search?type=USER`) để mở hồ sơ/gửi lời mời; không triển khai module tìm kiếm toàn cục, tìm bài viết, lịch sử hay từ khóa thịnh hành.

---

## 2. Mất mạng là tiêu chí nghiệm thu bắt buộc

**Thầy sẽ ngắt kết nối mạng trong lúc kiểm tra bài tập lớn** (bật chế độ máy bay, rút Wi-Fi, đổi mạng 4G), quan sát việc gọi API, nội dung hiển thị còn lưu trên máy và cách app xử lý tình huống vận hành. Mỗi feature phải xử lý cả luồng lỗi.

1. **Bảng tin / Thông báo / Tin nhắn** giữ nội dung đã cache khi offline hoặc refresh thất bại; không xóa nội dung cũ để hiện trang lỗi toàn màn hình. Ảnh chưa được lưu cần fallback, không giả vờ đã có dữ liệu.
2. Validate input ở client trước khi kiểm tra mạng/gửi request. Có Wi-Fi/mobile chưa chắc có Internet; vẫn bắt lỗi từng request.
3. Không báo thành công khi server chưa xác nhận, không loading vô hạn, không retry/polling liên tục.
4. Ngắt mạng giữa upload/đăng bài/gửi câu hỏi/chat phải giữ nội dung đang soạn (`DraftStore`) và thể hiện trạng thái gửi đúng.
5. Timeout có thể xảy ra sau khi server đã xử lý. **Không tự replay POST/PUT/PATCH/DELETE hoặc upload**; kiểm tra kết quả trước khi cho gửi lại để tránh trùng lặp bản ghi.
6. Khi mạng trở lại, refresh/đồng bộ có kiểm soát; tránh trùng bài/tin nhắn và request đồng thời không cần thiết.
7. Không xóa phiên chỉ vì offline/timeout/lỗi server. Phân biệt lỗi mạng với token bị server từ chối, quyền truy cập bị thu hồi và nội dung đã xóa.
8. Cache/bản nháp phải tách theo tài khoản (`userId`), không lộ dữ liệu user cũ sau logout hoặc đổi tài khoản. Dispose controller/subscription và bỏ response cũ khi màn hình/phiên không còn phù hợp.
9. Xử lý thêm lỗi server, JSON sai/rỗng, hết trang, quyền thiết bị bị từ chối, token hết hạn, app chạy nền và đóng/mở lại.
10. Kiểm thử trên điện thoại thật các bước ngắt mạng trước/trong thao tác và khôi phục mạng. Mock/unit test không thay cho nghiệm thu này.

### Các tình huống kiểm thử mở rộng cần dự kiến

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

---

## 3. Hiện trạng codebase — Cập nhật 12/11/2026

- **Mục 1 (`features/auth`, `features/settings`):** Đã có màn đăng nhập qua API, lưu phiên, callback refresh, đăng xuất cục bộ/server và đổi mật khẩu. `main.dart` gắn `AuthApplication` vào khung qua builders/routes công khai. Đã sửa mã thành công mặc định trong `AppConfig` thành **`1000`** theo response server thật. `android/gradle.properties` đặt `kotlin.incremental=false` để tránh lỗi cache khi project ở D: và Pub cache ở C:.
- **Mục 4 (`features/profile`, `features/relationships` — cập nhật 04/11):** Đã nối tab Cá nhân (`ProfileScreen`) và tab Bạn bè (`RelationshipsScreen`, `FriendFinderScreen` tìm người qua `GET search?type=USER`), có danh sách chặn, `SocialChanges`/`SocialLease` vô hiệu dữ liệu khi quan hệ thay đổi, route `ProfileRoutes.user` (`/profile/user`). Xem [bàn giao hồ sơ và quan hệ](docs/module-ho-so-quan-he.md).
- **Mục 3 (`features/question_bank` — cập nhật 10/11):** Đã nối `AppTab.questionBank` (`QuestionBankTab`) và `QuestionBankRoutes.routes` (`/question-bank/compose`, `/question-bank/submission`, `/question-bank/practice`, `/question-bank/ratings`). Xem [bàn giao mục 3](docs/muc-3-question-bank.md).
- **Mục 5 (`features/notifications`, `features/chat`, `features/settings` trên nhánh `feat5`):** Đã nối `AppTab.notifications` (`NotificationsTab`), `/conversations` (`ConversationsScreen`), `/chat` (`ChatDetailScreen`), `SettingsRoutes.pushSettings` (`/settings/push`), cùng GitHub Actions workflow build APK debug. Đã đối chiếu OpenAPI trực tiếp ngày 12/11/2026.
- **Chưa có:** `features/feed`, `features/posts` (chờ thành viên 2 merge).

---

## 4. Thành phần có sẵn — Tái sử dụng trước khi tạo mới

| Vị trí | Thành phần và mục đích |
| --- | --- |
| `lib/main.dart` | `AppBootstrap`: khởi tạo dependency, loading/thử lại khi lỗi, gọi `AuthApplication` |
| `lib/app/app.dart` | `SqbApp`: locale vi, lifecycle, điểm gắn màn hình qua router và shell |
| `lib/app/app_dependencies.dart`, `app_scope.dart` | `AppDependencies`, `AppScope.of(context)` cung cấp service dùng chung (`mediaUpload`, `api`, `cache`, `drafts`, `session`, `connection`) |
| `lib/app/router/app_router.dart` | `AppRoutes`, `AppRouter`: bảo vệ route bằng phiên, màn chưa tìm thấy |
| `lib/app/app_shell.dart` | `AppShell`, `AppTab`: feed, questionBank, friends, notifications, profile |
| `lib/app/theme/` | `AppColors`, `AppTheme`: màu tập trung, theme Material 3 tiếng Việt |
| `lib/core/config/app_config.dart` | `AppConfig`: HTTPS base URL, timeout, success code (`1000`) |
| `lib/core/network/api_client.dart` | `ApiClient`: get/request, Bearer token, envelope, lỗi, cancel/progress, điểm nối refresh token |
| `lib/core/network/connection_monitor.dart` | `ConnectionMonitor`, `DeviceConnectionMonitor`, `ConnectionStatus`: unknown/offline/available |
| `lib/core/errors/app_failure.dart` | `AppFailure`, `FailureKind`, `canUseCache`: lỗi thống nhất để UI xử lý |
| `lib/core/storage/` | `KeyValueStore`, `SessionStore`, `JsonCache`, `CachedResourceController<T>`, `DraftStore` |
| `lib/core/media/media_upload_service.dart` | `MediaUploadService`, `MediaPurpose`, `UploadedMedia`: upload multipart, kiểm tra dung lượng, progress/cancel |
| `lib/core/widgets/` | `AppButton`, `AppTextField`, loading/empty/error, `ConnectionBanner`, `AppNetworkImage`, `AppAvatar`, `CachedResourceView<T>` |
| `lib/core/validation/validators.dart` | `Validators`: bắt buộc, đếm từ, giới hạn số từ |
| `lib/features/auth/` | `AuthApplication`, `AuthController`, `AuthRepository`, `DeviceIdentity`, `LoginScreen` |
| `lib/features/profile/`, `relationships/` | `ProfileScreen`, `ProfileRoutes.user`, `RelationshipsScreen`, `FriendFinderScreen`, `SocialChanges` |
| `lib/features/question_bank/` | `QuestionBankTab`, `QuestionBankRoutes` |
| `lib/features/settings/` | `SettingsScreen`, `SettingsRoutes`, `ChangePasswordScreen`, `PushSettingsScreen` |

Dependencies đã có trong `pubspec.yaml`: Flutter localizations, `dio`, `flutter_secure_storage`, `shared_preferences`, `connectivity_plus`, `cached_network_image`, `image_picker`, `path_provider`.

---

## 5. Quy tắc tích hợp feature & Bảo vệ phần dùng chung

- **Nguyên tắc bất khả xâm phạm:** Khi làm việc trên nhánh feature (như `feat5`), **ưu tiên tái sử dụng `core` và `app`. Tuyệt đối không tự ý sửa đổi code dùng chung hoặc code của thành viên khác** để ép phục vụ feature của mình.
- **Điểm kết nối:** Mọi feature được gắn thông qua các API công khai của `AuthApplication` (`tabBuilders` và `protectedRoutes`) trong `lib/main.dart`.
- **Giao diện đồng nhất:**
  - Tái sử dụng bảng màu `AppColors` và typography từ `Theme.of(context)`. Không tạo bảng màu hay theme riêng lẻ.
  - Sử dụng chung thuật ngữ tiếng Việt: "Đang gửi…", "Thử lại", "Đã gửi", "Đã xem", "Không có kết nối mạng".
  - Các trạng thái phải dùng widget chuẩn: `AppLoadingState`, `AppEmptyState`, `AppErrorState`, `ConnectionBanner`.
- **Cache & Bản nháp:**
  - `JsonCache`: Lưu trữ dữ liệu cục bộ theo `userId` (giới hạn 512 KiB/record, tối đa 30–50 bản ghi).
  - `DraftStore`: Lưu văn bản đang gõ dở vào secure storage; tự động phục hồi khi mở lại và xóa sau khi gửi thành công.

---

## 6. Hợp đồng nghiệp vụ & API cần nhớ

- **Base URL:** `https://snsqb.duckdns.org/api/v1/`
- **Mã thành công chuẩn:** **`1000`** (Swagger minh họa `0000` không khớp server thật).
- **Header bắt buộc:** `Authorization: Bearer <access_token>` (trừ login/refresh).
- **Kiểu dữ liệu theo OpenAPI thực tế (cập nhật 12/11/2026):**
  - `CursorPaginationDto.after` và `before` là **số nguyên (`int64`)**, luôn đọc qua `?.toString()`.
  - `CreateDirectConversationDto` gửi `target_user_id` dạng **số nguyên (`int64`)**; response `ConversationDetailDto` trả `conversation_id`, `name`, `avatar_url`, `members`.
  - `NotificationTargetDto` dùng `target_id` (int64) và `type` enum `BADGE | SESSION | POST | QUESTION | USER | CONVERSATION`.
  - `PushSettingsResponseDto` & `UpdatePushSettingsRequestDto` dùng **boolean** (`true`/`false`) cho `push_enabled`, `sound_enabled`, `vibration_enabled`, `categories[K].enabled`; các key category là `SOCIAL`, `ACADEMIC`, `GAMIFICATION`, `SYSTEM`.
  - `SyncFidRequest` (`POST /devices/fid`) gửi `{"fid": "..."}`.
- **Giới hạn bài viết & bình luận:** Tối đa 500 từ; tối đa 4 ảnh hoặc 1 video (1–10 giây, tối đa 10 MB).
- **Đánh giá câu hỏi:** Thang điểm từ **0 đến 4** (0 là giá trị hợp lệ).
- **Không gọi API admin từ ứng dụng di động.**

---

## 7. Ranh giới công việc của 5 thành viên

| Thành viên | Nhánh Git | Phạm vi chủ trì |
| :---: | :---: | :--- |
| **1** | `main` / `feat1` | `app`, `core`, `features/auth`, ghép menu settings, cấu hình Android và tích hợp |
| **2** | `feat2` | `features/feed`, `features/posts`; media picker/viewer và bình luận |
| **3** | `feat3/dat` | `features/question_bank` (đóng góp câu hỏi, theo dõi duyệt, luyện tập) |
| **4** | `feat4` | `features/profile`, `features/relationships`; tìm người trong Bạn bè, danh sách chặn |
| **5** | **`feat5`** | **`features/chat`, `features/notifications`; cài đặt thông báo trong settings** |

---

## 8. Hướng dẫn chi tiết cho AI Model trên nhánh feat5 (Thành viên 5)

Nhánh **`feat5`** chịu trách nhiệm toàn bộ các tính năng liên quan đến **Thông báo**, **Trò chuyện 1–1 Realtime & Offline**, và **Cài đặt thông báo & Quản trị thiết bị**:

### A. Hệ thống Thông báo (`lib/features/notifications`)
- `NotificationsTab` gắn vào `AppTab.notifications` của `AppShell`, hỗ trợ bộ lọc (Tất cả / Chưa đọc / Ngân hàng đề), Pull-to-refresh, Infinite Scroll (`after`, `has_next`), Optimistic read (`POST /notifications/{id}/read`, `POST /notifications/read-all`).
- `NotificationDeepLinkHandler` điều hướng tới `ChatDetailScreen`, `ProfileRoutes.user`, `QuestionBankRoutes.submission`, `/posts/detail` và bắt lỗi an toàn (không crash khi 404/403 hoặc route chưa merge).
- Offline cache qua `JsonCache` theo `userId`.

### B. Trò chuyện 1–1 Realtime & Offline (`lib/features/chat`)
- Chỉ làm **chat 1–1 (Direct chat)**, không làm chat nhóm; không hỗ trợ tag `@username`.
- `ConversationsScreen` (`/conversations`): `GET /conversations`, tạo chat 1–1 `POST /conversations/direct`, tìm kiếm nhanh, cache offline.
- `ChatDetailScreen` (`/chat`): `GET /conversations/{id}/messages`, Reverse scroll, bong bóng chat, trạng thái Đang gửi / Đã gửi / Lỗi thử lại, xem ảnh toàn màn hình phóng to (`InteractiveViewer`), cảnh báo khi bị chặn, upload ảnh qua `deps.mediaUpload` (`MediaPurpose.chat`, $\le 4\text{MB}$).
- STOMP WebSocket WSS (`wss://snsqb.duckdns.org/api/v1/ws`): subscribe `/user/queue/messages`, `/topic/conv.{id}.typing`; send `/app/chat.send`, `/app/chat.read`, `/app/chat.typing`.
- `ChatEmoteConverter`: chuyển đổi ký tự emote (bao gồm `<(")` → 🐧, `(^^^)` → 🦈, `:))` → 😆, `:)` → 😊, `<3` → ❤️, v.v.).
- Lưu nháp qua `DraftStore`, chống duplicate/replay bằng `client_msg_id`.

### C. Cài đặt Thông báo & Thiết bị (`lib/features/settings`)
- `PushSettingsScreen` (`SettingsRoutes.pushSettings = '/settings/push'`): `GET /settings/push`, `PUT /settings/push`, công tắc chuyên mục (`SOCIAL`, `ACADEMIC`, `SYSTEM`), rung/chuông, tùy chọn kiểu âm thanh mặc định hoặc giọng nói thu âm (Slide 26 & 29), đăng ký/hủy thiết bị (`POST /devices/fid`, `POST /devices/fid/unregister`).

---

## 9. Kiểm tra và bàn giao

```sh
flutter pub get
dart format lib test
flutter analyze --no-pub
flutter test --no-pub
```

- Không đưa password/token vào source code, log, fixture, dart-define hoặc Git.
- Nếu cần build APK trên máy có ít RAM, sử dụng GitHub Actions workflow `.github/workflows/build-apk.yml` hoặc tạm giảm `org.gradle.jvmargs` khi build local (không commit đè file cấu hình chung nếu không được giao).
