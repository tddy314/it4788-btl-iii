# Mục 2 — Bảng tin và bài viết

Cập nhật 07/11/2026. Đã nối phần 2 vào tab Bảng tin sau đăng nhập. Phần kiểm chứng trên thiết bị nằm ở cuối tài liệu.

## Phạm vi và nguồn

- Flutter Android; frontend dùng backend của thầy. Đọc `AGENTS.md` trước khi sửa.
- Nguồn yêu cầu đầy đủ: `../Social_Network_Student_Generated_Question_Bank_FULL.md` ở thư mục cha repo (207 slide). Phần bài viết: slide 23–29, phi chức năng 35–39, API 132–151, 157 và báo cáo 179. Những API ngoài phần 2 chỉ đọc để hiểu hệ thống, không triển khai ngoài phân công.
- Swagger: https://snsqb.duckdns.org/api/v1/swagger-ui/index.html ; OpenAPI: https://snsqb.duckdns.org/api/v1/docs/openapi.json . Đã đọc schema endpoint liên quan ngày 04/11/2026.

- Không lưu tài khoản, mật khẩu, token thật vào source/test/tài liệu. Login Android bằng thông tin người dùng cấp đã trả HTTP 200/code 1000, đủ access/refresh token. Các bài kiểm thử ghi chỉ được tạo bằng tài khoản đã cho phép và đã được dọn sau khi đối chiếu.

## Kết quả đối chiếu API

- `activity-feeds` trả sự kiện đa loại; tài khoản thật hiện có hai sự kiện `SESSION_RESOLVED_APPROVED`, `target_type=SESSION`, content chứa title/subject/counters. Không coi đó là Post, không suy luận mọi câu đã duyệt.
- `posts/me` và `video-posts` trả danh sách rỗng, envelope code 1000. `activity-feeds/new-count` trả `{new_count: 0}`, `since` dùng epoch milliseconds.
- Post tạo: `POST posts`, JSON PUBLIC/SOCIAL_POST; media là object `MediaItem` (key/url/type/width/height/size/duration), không phải string URL.
- Sửa: `PUT posts/{id}` chỉ trả post_id/updated_at; phải tải chi tiết sau xác nhận, không parse như Post đầy đủ. Xóa trả post_id.
- Like: `POST react` luôn gửi `reaction_type=LIKE`; server toggle, không gửi NONE. Đọc my_reaction/total_count.
- Bình luận: GET/POST comments, target_type POST, target_id; trả lời dùng parent_comment_id. Không UI sửa/thả cảm xúc/ảnh bình luận. Chỉ tác giả bình luận được xóa, chủ bài không tự có quyền xóa bình luận người khác.
- Media: `medias/upload` (số nhiều), multipart file + query purpose POST; `video-posts` (dấu gạch ngang) là video bài giảng. Không dùng đường dẫn tài liệu cũ.
- Report enum schema: SPAM/HARASSMENT/HATE_STATEMENT/OTHER; description <=500 ký tự. API chưa có endpoint đối soát báo cáo đã gửi.
- 500 **từ** cho bài/bình luận. 4 ảnh tĩnh hoặc 1 video, không trộn. Ảnh <=4 MiB; video <=10 MiB, dài 1–10 giây. Chọn/chụp ảnh và chọn/quay video; validate nội dung file, không tin đuôi file.

## Cấu trúc phần 2

- `features/feed`: DTO sự kiện, repository và màn bảng tin.
- `features/posts`: DTO/repository, phân trang có cache tùy chọn, card/chi tiết, soạn bài/controller, media service/viewer, danh sách bài của tôi/video, bình luận và báo cáo.
- Chỉ gắn thêm builder feed trong `features/auth/auth_application.dart` (điểm composition đã được nhóm quy định). Không sửa implementation app/core/theme.
- Tái sử dụng ApiClient, SessionStore, JsonCache, DraftStore, AppNetworkImage/AppAvatar và widget trạng thái/theme.
- Thêm image_picker 1.2.4, video_player 2.14.1, path_provider 2.1.6. Media adapter trong feature dùng ApiClient vì wrapper upload chung chưa có tham số MIME multipart; không thay core.
- Cache giới hạn 40 mục/record và 512 KiB, tối đa 200 mục RAM; theo user. GET lỗi mạng giữ dữ liệu, 401/403/404 bỏ dữ liệu và cache. Draft secure theo user; file nháp trong application support riêng theo user.
- Ghi trạng thái chưa rõ trước thao tác gửi để phục hồi khi process chết. Không auto replay. Like mất phản hồi phải GET lại; bài/bình luận phải kiểm tra trước khi người dùng xác nhận gửi lại.

## Kiểm chứng và tiếp tục công việc

Ngày 05/11/2026, Flutter 3.47.9 với Dart 3.13.7 đã resolve đúng pubspec.lock. Đã format các file của phần 2. flutter analyze --no-pub báo No issues found. flutter test --no-pub đạt 61/61, gồm 31 kiểm thử cũ và 30 kiểm thử cho phần 2. Các test mới dùng transport/storage giả có kiểm soát.

| Tình huống | Kết quả đã kiểm tra |
| --- | --- |
| Khởi động với phiên A và feed đã lưu, thiết bị báo offline | Nội dung vẫn hiển thị sau refresh. Transport nhận 0 request. Có mạng trở lại và refresh sẽ nhận trang mới. |
| Server trả 403, một trang sai cấu trúc hoặc ghi cache thất bại | 403 xóa nội dung/cache liên quan. Lỗi tải lại giữ danh sách đang đọc. Lỗi ghi cache không biến lần tải thành lỗi API. |
| Tải thêm gặp item trùng hoặc cursor lặp | Ghép theo ID và dừng khi cursor không tiến. Kết quả trang cũ không khôi phục bài đã xóa hay ghi đè lượt thích vừa xác nhận. |
| Đổi tài khoản hoặc đăng xuất lúc đang tải | Bỏ kết quả đến muộn. Bản nháp và cache của tài khoản cũ không xuất hiện trong tài khoản mới. |
| Tắt mạng trước gửi hoặc mất phản hồi sau gửi | Validate 500 từ trước khi gọi mạng. Giữ bản nháp. Gửi hai lần liên tiếp chỉ tạo một request khi đang bận. |
| Gián đoạn ở ảnh thứ hai | Lưu kết quả ảnh thứ nhất. Sau mở lại, chỉ tiếp tục với tệp được chọn lại. Không tạo bài thiếu ảnh. |
| Server nhận lượt thích nhưng mất phản hồi | Đối chiếu trạng thái bằng GET trước thao tác toggle. Nếu trạng thái đã đúng ý người dùng thì cập nhật thẻ bài. |
| Màn 360×640 với chữ lớn, bàn phím mở | Widget test đã cuộn đến nút gửi, nhập tiếng Việt và kiểm tra nội dung/lỗi ở màn soạn bài và bình luận. |

Lệnh chạy lại tại thư mục gốc repo:

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build apk --release --split-per-abi --target-platform android-arm64,android-x64 --no-pub
```

Nếu analyzer trên Windows gặp lỗi LSP với đường dẫn Unicode, có thể ánh xạ thư mục repo đến một ký tự ổ đĩa trống bằng subst rồi chạy các lệnh trên trong ổ đó.

### Kết quả trên Android ngày 05/11/2026

Đã build hai APK release từ mã hiện tại. Bản cho điện thoại ARM64 ở `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (khoảng 20 MiB), đã kiểm tra chữ ký bằng apksigner. Bản x86_64 cho máy ảo ở `build/app/outputs/flutter-apk/app-x86_64-release.apk` (khoảng 21 MiB). APK dùng cấu hình ký debug hiện có của nhóm cho mục đích cài thử.

- Đăng nhập qua giao diện trên máy ảo Android x86_64 bằng tài khoản HUST được cấp, tải được hai sự kiện duyệt câu hỏi từ server thật. Tại thời điểm thử, tài khoản chưa có bài viết cá nhân và danh sách video bài giảng rỗng.
- Bản release ban đầu đọc/ghi cache thất bại dù các test dùng storage giả đạt. Sau khi chỉ cập nhật bản khóa Android của shared_preferences từ 2.5.1 lên 2.5.4, cùng luồng đăng nhập và feed hoạt động qua lần khởi động lạnh. Bản 2.5.2 của plugin đã bổ sung quy tắc R8 giữ các lớp Kotlin mà JNI sử dụng trong bản release. [Changelog của plugin](https://pub.dev/packages/shared_preferences_android/changelog)
- Bật chế độ máy bay, tắt Wi-Fi và dữ liệu di động, xác nhận Android báo `Active default network: none`. Buộc đóng tiến trình rồi mở lại, app giữ phiên, hiển thị thời điểm lưu và nội dung sự kiện. Bấm đúng nút **Thử lại** khi offline vẫn thấy sự kiện. Bật mạng và bấm **Thử lại** tải lại được feed trực tiếp. Ảnh chụp lúc offline nằm ở `build/device-qa/feed-offline.png`.
- Trong chế độ máy bay, bấm đăng khi nháp rỗng hiển thị lỗi nhập liệu. Đã chọn một ảnh PNG bằng bộ chọn ảnh Android, nhập văn bản rồi bấm đăng khi mạng bị ngắt. Sau khi buộc đóng và mở lại, cả văn bản và ảnh đều xuất hiện trong trình soạn. Đã cài lại bản release cuối cùng và kiểm tra lại khôi phục cache/nháp.
### Kiểm thử ghi trên backend thật ngày 05/11/2026

| Ca thử | Thao tác đã thực hiện | Đối chiếu độc lập |
| --- | --- | --- |
| Bài ảnh #152 | Upload PNG 320×180 qua multipart, tạo bài PUBLIC/SOCIAL_POST, thích, bình luận, sửa nội dung. | GET chi tiết trả LIKE, 1 lượt thích, 1 bình luận. GET comments trả đúng nội dung/tác giả. Bài sau sửa giữ nguyên media. CDN trả HTTP 200 và đúng 2.949 byte tệp gốc. |
| Bài video #153 | Trên app Android release, chọn MP4, đăng, mở trình phát, phát hết clip, thích, gửi bình luận và sửa bài. | GET chi tiết trả VIDEO 2 giây, nội dung mới, media giữ nguyên, LIKE và 1 bình luận. GET comments có bình luận vừa gửi. CDN trả đúng 24.477 byte MP4 gốc. |
| Dọn dữ liệu | Bỏ thích, xóa bình luận thử và xóa cả hai bài. Riêng video thực hiện qua UI Android. | GET từng bài trả HTTP 404/code 2009, posts/me trở về 0 như trước thử. HEAD đến từng URL CDN kèm query mới trả 404. |

Sau xóa, activity-feeds vẫn có thể trả sự kiện CREATED_POST trỏ đến bài đã mất. Frontend kiểm tra chi tiết theo target_id, bỏ bài bị trả 403/404 và loại bản tương ứng khỏi cache đang hiển thị. Nếu cả trang chỉ còn các sự kiện như vậy, nút tải thêm vẫn hoạt động khi cursor tiến. Test hồi quy bao phủ hai trang liên tiếp bị lọc hết rồi tới một bài còn quyền đọc. Video thiếu thumbnail có nút “Xem video” riêng, tránh chồng biểu tượng ảnh lỗi lên nút phát.

Lượt kiểm thử này dùng Android ảo và tài khoản thật. Hai điện thoại thật, camera/quyền ở các phiên bản Android và báo cáo vi phạm thực tế vẫn cần môi trường nghiệm thu phù hợp.

### Kiểm tra bài ảnh offline và dọn dữ liệu ngày 07/11/2026

- Đã đọc lại OpenAPI, đăng nhập lại bằng tài khoản được cho phép và xác nhận `posts/me` rỗng trước lượt thử.
- Trên APK release x86_64, khôi phục bản nháp sau khi mở lại app, chọn ảnh từ thư viện Android và đăng bài #253. GET độc lập xác nhận bài IMAGE có tệp PNG 2.949 byte; nội dung tải từ CDN trùng từng byte với ảnh gốc.
- Mở ảnh khi có mạng rồi quay về bảng tin để lưu cache. Bật chế độ máy bay, tắt Wi-Fi/dữ liệu di động và xác nhận `Active default network: none`. Force-stop rồi mở lại app vẫn thấy văn bản và ảnh của bài. Bấm **Thử lại** khi offline giữ nguyên nội dung. Ảnh chụp bằng chứng được giữ cục bộ ở `build/live-media-qa/image-offline.png`, không đưa vào Git.
- Bật lại mạng, mở chi tiết và xóa bài qua giao diện. GET bài #253 trả HTTP 404/code 2009, `posts/me` trở về 0, HEAD URL ảnh với query mới trả 404. Không còn bài, lượt thích hay bình luận thử đang tồn tại. Sự kiện hoạt động cũ do server giữ lại không có API xóa trong phạm vi frontend; app lọc những sự kiện trỏ tới bài 403/404.
- Chạy lại analyzer qua ổ đĩa ánh xạ trên Windows, kết quả `No issues found`. Nhánh bàn giao là `feat2`, giữ nguyên `main` để nhóm review và tích hợp. Không đưa APK, file thử, cache, tài khoản hay token vào commit.

## Kịch bản nghiệm thu trên điện thoại

1. Đăng nhập, tải bảng tin, mở một bài công khai có ảnh và ghi nhận nội dung, lượt thích. Tắt Wi-Fi và dữ liệu di động, kéo làm mới rồi đóng/mở lại app. Bài đã lưu phải còn. Ảnh chưa tải cần có trạng thái thay thế. Video mạng cần Internet.
2. Trong lúc offline, gửi bài rỗng và bài quá 500 từ để kiểm tra lỗi nhập liệu. Soạn nội dung hợp lệ, đính kèm tệp, thoát rồi mở lại để kiểm tra nháp. Khi mạng trở lại, người dùng chủ động gửi.
3. Kiểm tra camera/thư viện với ảnh thứ 5, ảnh động, video dưới 1 giây/trên 10 giây và tệp vượt giới hạn. Tắt mạng giữa hai ảnh upload. Kiểm tra tệp đã xác nhận và bài viết trên server trước khi thử lại.
4. Trên bài thử được phép đăng, kiểm tra sửa/xóa bài, thích/bỏ thích nhanh và bình luận. Ngắt mạng khi server đang xử lý để kiểm tra trạng thái chưa rõ kết quả. Báo cáo vi phạm chỉ dùng với đối tượng thử phù hợp.
5. Đăng xuất, đổi tài khoản, thử Back và kiểm tra dữ liệu cũ. Dùng hai tài khoản thử để xác nhận phản hồi khi bài bị xóa/thay đổi quyền khi đang mở.

Để tiếp tục phát triển, đọc AGENTS.md và chạy lại các kiểm tra ở trên với dependency lock của repo.
