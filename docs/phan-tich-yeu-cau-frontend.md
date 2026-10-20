# Phân tích frontend Android — SQB

Ngày đối chiếu: 18/10/2026. Phạm vi theo yêu cầu: ứng dụng Flutter cho Android mobile, toàn bộ giao diện tiếng Việt, dùng backend có sẵn của thầy.

Đã xác nhận từ người dùng: **không làm luồng đăng ký; giảng viên cấp tài khoản để đăng nhập**. Nhóm có 5 thành viên; xem [phân công công việc](phan-cong-nhom.md).

Cập nhật phạm vi ngày 20/10/2026: **bắt buộc đăng nhập trước khi xem bảng tin, không có chế độ khách**. Thầy sẽ ngắt mạng khi kiểm tra: cần giữ bài viết đã cache khi còn phiên đăng nhập, xử lý lỗi API, giữ bản nháp và tránh gửi trùng khi kết nối lại. Đây là yêu cầu xuyên suốt cho mọi tính năng; xem mục “Lưu ý bắt buộc xuyên suốt khi code và kiểm thử” trong tài liệu phân công.

## 1. Nguồn và mức độ xác nhận

- PDF: [Social Network for Student-Generated Question Bank.pptx.pdf](<Social Network for Student-Generated Question Bank.pptx.pdf>), 208 trang.
- [Swagger UI](https://snsqb.duckdns.org/api/v1/swagger-ui/index.html).
- [OpenAPI JSON](https://snsqb.duckdns.org/api/v1/docs/openapi.json): phiên bản tài liệu 1.0.0, kiểm đếm được 128 đường dẫn và 146 thao tác HTTP tại thời điểm đọc.
- Đã đọc đặc tả công khai, chưa đăng nhập, chưa gửi dữ liệu nghiệp vụ và chưa kiểm thử hành vi thực tế của server. Ví dụ trong Swagger không phải tài khoản thử nghiệm được xác nhận.
- Mục dưới đây phân biệt yêu cầu trong PDF, hợp đồng API hiện tại và đề xuất triển khai. Khi hai nguồn mâu thuẫn về nghiệp vụ, cần xác nhận với giảng viên; không mặc định mọi chức năng API hỗ trợ đều phải đưa vào app.

## 2. Bản chất đề tài và phạm vi

Đây là mạng xã hội học tập có luồng sinh viên đóng góp câu hỏi vào ngân hàng đề theo môn học. Hai phần phải gắn kết: giao diện và tương tác quen thuộc như Facebook; nghiệp vụ nộp, theo dõi, luyện tập và đánh giá câu hỏi (PDF trang 5, 23–32).

Chỉ làm frontend vẫn bao gồm quản lý trạng thái, validation, gọi API, phiên đăng nhập, upload ảnh/video, cache trên máy, chat realtime và xử lý lỗi. Không triển khai Spring Boot, cơ sở dữ liệu, Redis, thuật toán AI, kiểm tra đạo văn, tính điểm hay server duyệt câu hỏi.

Vai trò chính của bản Android đầu tiên là **sinh viên**. Giảng viên duyệt câu hỏi trên hệ thống của thầy. Màn hình quản trị, duyệt đề và sinh đề thi cho giảng viên nằm ngoài phạm vi đề xuất hiện tại; PDF có liệt kê chúng là chức năng của toàn hệ thống nên cần đối chiếu cách chấm cho riêng nhóm mobile.

Hiện trạng mã nguồn: `lib/main.dart` và `test/widget_test.dart` vẫn là Flutter counter mẫu; chưa có màn hình nghiệp vụ, client API hay quản lý đăng nhập. `pubspec.yaml` mới có Flutter và Cupertino Icons. Manifest Android bản main chưa khai báo quyền Internet.

## 3. Phạm vi chức năng đề xuất

| Mức ưu tiên | Phần việc frontend | Kết quả cần có |
| --- | --- | --- |
| P0 | Nền tảng và đăng nhập | Theme tiếng Việt, routing, validation, lưu phiên, refresh token, đăng xuất, xử lý lỗi |
| P0 | Đóng góp ngân hàng câu hỏi | Chọn môn đang học, nhập bộ câu hỏi/đáp án, đính ảnh, khai báo nguồn AI/tự làm, gửi đề xuất |
| P0 | Đề xuất của tôi | Danh sách, bộ lọc, chi tiết, theo dõi kết quả, sửa/xóa khi còn được phép |
| P0 | Bảng tin và tương tác | Xem bài, đăng/sửa/xóa bài của mình, like, bình luận, báo cáo |
| P1 | Luyện tập và đánh giá | Trả lời câu hỏi đã công bố, xem kết quả server trả về, chấm 0–4, báo câu lỗi |
| P1 | Quan hệ và hồ sơ | Kết bạn, xử lý lời mời, theo dõi giảng viên, chặn/bỏ chặn, xem/sửa hồ sơ |
| P1 | Tìm kiếm và thông báo | Tìm nội dung/người dùng, lịch sử, đọc thông báo, mở đúng màn hình liên quan |
| P1 | Chat 1–1 | Hội thoại, lịch sử, gửi/nhận realtime, đã đọc, đang nhập, xử lý mất kết nối |
| P2 | Hoàn thiện media và push | Camera, quay/chọn video, xem media, thông báo đẩy và cài đặt âm thanh |
| P2 | Gamification | Bảng xếp hạng, dự đoán, huy hiệu nếu còn thời gian và đủ hợp đồng API |

Đây là thứ tự triển khai, không phải phép quy đổi điểm. PDF trang 19 nêu điều kiện tối thiểu 70% chức năng để được điểm tối đa, nhưng chưa có mẫu số/trọng số đủ rõ để cam kết một MVP đạt tỷ lệ đó. Trang 32 ưu tiên Auth, đề xuất câu hỏi, tạo đề thi, Post, Comment, Like, Block, Friend và Chat 1–1 trước AI/minigame.

## 4. Điều hướng và luồng chính

Đề xuất thanh điều hướng dưới gồm **Bảng tin · Ngân hàng câu hỏi · Bạn bè · Thông báo · Cá nhân**. Tìm kiếm và tin nhắn mở từ thanh trên. Video mở từ bảng tin/menu; thêm tab riêng khi phạm vi demo cần. Đây là quyết định thiết kế đề xuất, không phải bố cục bắt buộc trong PDF.

Luồng trọng tâm:

1. Đăng nhập bằng email trường và tài khoản được cấp.
2. Vào Ngân hàng câu hỏi → Đề xuất câu hỏi → chọn môn đang theo học.
3. Nhập tiêu đề bộ câu hỏi, mô tả/nguồn tham khảo; thêm từng câu với nội dung, ảnh nếu có, phương án, đáp án đúng, giải thích, nguồn tự làm/AI và mức tự tin 0–4.
4. Xem lại → upload ảnh → gửi bộ câu hỏi → mở chi tiết đề xuất vừa gửi.
5. Theo dõi ở Đề xuất của tôi; cho sửa/xóa khi phiên `PENDING` và server cho phép.
6. Khi có câu hỏi được công bố, người học khác mở phiên để luyện tập, đánh giá và thảo luận.

Phải phân biệt **session đề xuất** với phiên đăng nhập, và **trạng thái phiên** với kết quả duyệt từng câu. Bộ lọc phiên hiện dùng `PENDING` / `REVIEWING` / `RESOLVED`, tương ứng Chờ duyệt / Đang duyệt / Đã xử lý. Không đổi `RESOLVED` thành “Tất cả đã được duyệt”. Schema chi tiết hiện thiếu một số trường trạng thái; cần kiểm tra response thật trước khi chốt UI.

Các nhóm màn hình cần thiết: đăng nhập; bảng tin; trình soạn bài; chi tiết bài/bình luận; xem ảnh/video; chọn môn; soạn bộ câu hỏi; xem lại; danh sách/chi tiết đề xuất của tôi; luyện tập; đánh giá; bạn bè/lời mời; hồ sơ; tìm kiếm; thông báo; hội thoại/chat; cài đặt/đổi mật khẩu/danh sách chặn. Mỗi nhóm có trạng thái loading, rỗng, lỗi và thử lại phù hợp.

## 5. Bản đồ API cho frontend

Base URL: `https://snsqb.duckdns.org/api/v1`. Các đường dẫn trong bảng được ghép sau base URL.

| Nghiệp vụ | API hiện có |
| --- | --- |
| Phiên đăng nhập | `POST /auth/login`, `/auth/refresh`, `/auth/logout`, `/auth/change-password` |
| Hồ sơ | `GET/PUT /users/me`, `GET /users/{userId}` |
| Môn học | `GET /sessions/my-enrolled-subjects`, `GET /subjects` |
| Nộp bộ câu hỏi | `POST /sessions/propose` |
| Đề xuất của tôi | `GET /sessions/my-submissions`, `GET/PUT/DELETE /sessions/my-submissions/{sessionId}` |
| Câu hỏi luyện tập | `GET /users/{userId}/sessions`, `GET /sessions/{sessionId}/questions` |
| Trả lời và đánh giá | `POST /questions/{questionId}/answer`, `/questions/{questionId}/rate`; `GET /questions/{questionId}/ratings` |
| Bảng tin | `GET /activity-feeds`, `GET /activity-feeds/new-count` |
| Bài viết | `POST /posts`, `GET/PUT/DELETE /posts/{id}`, `GET /posts/me`, `GET /users/{userId}/posts` |
| Video | `GET /video-posts` |
| Bình luận và like | `GET/POST /comments`, `POST /react` |
| Upload | `POST /medias/upload?purpose=QUESTION` hoặc `POST`, `AVATAR`, `COVER`, `CHAT`; nâng cao: `/medias/presign`, `/medias/verify` |
| Bạn bè | `POST /friendships/request`, `/accept`, `/decline`; `GET /friendships`, `/friendships/requests/received`, `/friendships/requests/sent`; `DELETE /friendships/{friendId}` |
| Theo dõi | `POST/DELETE /follows/{targetUserId}`, `GET /follows/following`, `/follows/followers` |
| Chặn và báo cáo | `POST/DELETE /blocks/{targetUserId}`, `GET /blocks`, `POST /report` |
| Tìm kiếm | `GET /search`, `GET /search/saved`, `DELETE /search/saved/{id}` |
| Hội thoại | `GET /conversations`, `POST /conversations/direct`, `GET /conversations/{id}/messages` |
| Thông báo | `GET /notifications`, `POST /notifications/{id}/read`, `/notifications/read-all`; `GET/PUT /settings/push` |
| Thiết bị | `GET /devices`, `POST /devices/fid`, `POST /devices/fid/unregister` |
| Mở rộng | `GET /games/leaderboard`, `/games/my-predictions`; các API dự đoán, huy hiệu và cosmetics |

OpenAPI ghi rõ **không gọi API admin**. Không dùng `/auth/admin/*` để tạo luồng tự đăng ký trên mobile. Các API sinh đề `/exams/generate`, danh sách đề và xuất ngân hàng câu hỏi được mô tả dành cho giảng viên; không đưa vào luồng sinh viên chỉ vì tài liệu toàn hệ thống có chúng.

## 6. Hợp đồng dữ liệu cần chú ý

- Login cần `email`, `password`, `device_id`, `platform`; dùng `platform: ANDROID`. `device_id` cần ổn định theo cài đặt, không sinh mới sau mỗi lần login. Response có token và vai trò.
- Phản hồi chuẩn là `{code, message, data}`; OpenAPI minh họa mã thành công `"0000"`, PDF trang 68 ghi `"1000"`. Chưa xác nhận mã thật; không hardcode theo PDF hoặc coi HTTP 200 luôn là nghiệp vụ thành công.
- JSON chủ yếu dùng `snake_case`; ID thường là số nguyên, cờ là boolean, điểm là số. PDF nhiều bảng ghi chúng là string, nên DTO phải theo từng schema hiện tại và kiểm chứng response thật.
- Phân trang phổ biến dùng `after`, `limit`, `data.items`, `data.pagination.has_next`. Riêng tìm kiếm mô tả `after` như offset; phải đọc từng endpoint, không áp một quy tắc cursor cho toàn bộ API.
- Nộp phiên dùng JSON gồm `title`, `subject_id`, `questions`; mỗi câu cần `content`, `llm_generated`, `options`. `options` là object với `key`, `text`, `is_correct` và media tùy chọn, không phải danh sách chuỗi.
- Khi tạo câu dùng `llm_generated`; khi sửa dùng `source: LLM | HOMO_SAPIENS`; ảnh gửi bằng `media_urls` nhưng chi tiết có `image_urls`; mức tự tin gửi là `confidence`, đọc chi tiết là `confidence_score`. Cần mapping rõ ở tầng data.
- Upload trực tiếp dùng multipart trường `file`, query `purpose`; lấy URL trả về đưa vào request nghiệp vụ. Với bài viết, `media_urls` là mảng `MediaItem` chứa metadata; với câu hỏi là mảng URL. Không dùng chung một DTO cho hai request.
- Thang đánh giá là **0–4**, không phải 1–5 sao. Báo lỗi có `is_error`; server mô tả đặt điểm về 0 khi bật cờ này.
- Khi luyện tập, đáp án đúng bị ẩn cho đến khi trả lời. Không mặc định `is_correct` thiếu là false, không tự suy đáp án; dùng kết quả server. Request trả lời dùng `selected_options` và có thể gửi `question_updated_at` để phát hiện dữ liệu cũ.
- Feed có nhiều loại sự kiện và `content` là object tổng quát. Cần parser/card theo loại; có hiển thị dự phòng cho sự kiện chưa nhận diện.
- Logout hiện không khai báo request body, khác PDF; kiểm tra trước khi gửi các trường cũ.

## 7. Yêu cầu PDF dễ bỏ sót

- Bài viết và bình luận tối đa **500 từ**, không phải 500 ký tự (trang 23).
- Tối đa **4 ảnh hoặc 1 video**, không trộn ảnh/video; ảnh tối đa 4 MB, video tối đa 10 MB và thời lượng 1–10 giây (trang 23, 27). Cần xác nhận cách tính MB khi kiểm tra biên.
- Bản theo yêu cầu cơ bản chỉ có bài public và một loại like; không tự mở mọi tùy chọn Facebook (trang 23, 25).
- Không tag người dùng, không tạo nhóm xã hội, không chat nhóm trong phạm vi cơ bản; comment không có reaction, không cho chủ bài xóa comment của người khác, không cho sửa comment theo mô tả chức năng (trang 25–28).
- Có camera và quay video trong app, chọn media từ máy, xem ảnh/video, nút “Xem thêm” cho nội dung dài và nút đóng ứng dụng (trang 27–28).
- Chặn ảnh hưởng bạn bè, trang cá nhân, bình luận nhìn thấy và chat. UI phải cập nhật các vùng liên quan theo kết quả server, không chỉ đổi chữ trên một nút (trang 24).
- Validate input trước khi kiểm tra mạng/gọi API; thông báo lỗi tiếng Việt nhất quán; loading, timeout, response lỗi định dạng, pull-to-refresh, tải thêm và cache bảng tin (trang 35–39).
- Mã màu tập trung một nơi, tránh rải màu trực tiếp trong màn hình (trang 37).
- Demo IT4788 cần ít nhất **2 điện thoại thật**, mạng 3G/4G và chia sẻ màn hình USB để thử ngắt mạng; chỉ emulator là chưa đủ (trang 18).

## 8. Các điểm lệch cần chốt trước khi làm luồng phụ thuộc

| Vấn đề | PDF | Swagger hiện tại | Hướng xử lý đề xuất |
| --- | --- | --- | --- |
| Đăng ký, OTP, quên mật khẩu | Có luồng cho người dùng | Chỉ thấy `/auth/admin/register`, `/verify`, `/resend-verify`, `/reset-password` trong nhóm admin | Đã chốt bỏ đăng ký vì thầy cấp tài khoản. Không cần OTP kích hoạt từ luồng đăng ký. Không tự làm reset mật khẩu qua API admin; đổi mật khẩu sau đăng nhập là chức năng riêng |
| Nộp ZIP | Phần tổng quan API nhắc ZIP; chi tiết cũng có JSON | `/sessions/propose` nhận JSON | Làm form cấu trúc và ảnh; chưa cam kết nhập ZIP |
| Like và quyền riêng tư | Một like, public | Có LIKE/LOVE/WOW và PUBLIC/FRIENDS/ONLY_ME | Bản cơ bản chỉ hiển thị like/public, chờ xác nhận nếu mở rộng |
| Bình luận, nhóm, xóa tài khoản | Hạn chế sửa comment, không chat nhóm, không tự xóa tài khoản | Có API hỗ trợ các thao tác này | Không tự đưa vào app; API tồn tại không thay thế yêu cầu môn học |
| Nguồn AI ẩn với giảng viên | Yêu cầu rõ ở trang 30 | Một số DTO chứa `source` | App chỉ trình bày đúng vai trò; backend phải bảo đảm không rò rỉ. Cần xác nhận cơ chế ẩn |
| Trạng thái và kết quả duyệt | Có mô tả ở nhiều cấp | Enum phiên PENDING/REVIEWING/RESOLVED; một số mô tả còn nhắc APPROVED/REJECTED; chi tiết thiếu trạng thái | Kiểm tra payload thật và quy tắc quyền sửa/xóa; không tự suy kết quả |
| Push | PDF nhắc device token/FCM | API dùng tên FID | Cần xác nhận server cần Installation ID hay FCM registration token, cùng cấu hình Firebase cho app Android |
| Chat | Có STOMP destinations | Mô tả handshake `ws://<domain>/api/v1/ws` | Với domain HTTPS dự kiến dùng WSS; cần kiểm chứng proxy, handshake, native STOMP hay SockJS |
| Điểm tối đa | 70% chức năng, bao gồm tính năng toàn hệ thống | Một số chức năng chỉ cho giảng viên/admin | Cần rubric cho nhóm chỉ làm frontend mobile |

Không cần chờ các điểm này để làm theme, điều hướng, các trạng thái UI và mẫu màn hình bằng dữ liệu giả. Luồng tích hợp phụ thuộc phải được xác nhận trước khi coi là hoàn tất.

## 9. Kiến trúc Flutter đề xuất

Tổ chức theo tính năng: `auth`, `feed`, `posts`, `question_bank`, `friends`, `profile`, `search`, `chat`, `notifications`, `settings`. Phần chung gồm theme, routing, network, lưu trữ và widget dùng lại.

Trong từng tính năng, tách màn hình/widget, quản lý trạng thái và repository/DTO. UI phụ thuộc repository để có thể dùng dữ liệu giả lúc API chưa sẵn sàng rồi chuyển sang server thật. Không gọi HTTP trực tiếp trong widget.

Yêu cầu kỹ thuật cho nền tảng:

1. Một API client chung: base URL cấu hình được, Bearer token, timeout, mapping lỗi tiếng Việt; xử lý refresh token đồng thời và chặn vòng lặp refresh vô hạn. Không tự gửi lại thao tác nộp bài khi không biết server đã xử lý hay chưa.
2. Token lưu bằng cơ chế lưu trữ bảo mật của nền tảng; không lưu mật khẩu, không ghi token vào log. Cache bảng tin theo tài khoản và xóa/tách khi đổi tài khoản.
3. Quản lý trạng thái có loading/data/empty/error và trạng thái đang gửi; chặn bấm gửi lặp, giữ bản nháp khi lỗi hoặc rời màn hình.
4. Upload riêng khỏi tạo nội dung; hiển thị tiến trình, giữ draft nếu upload/gửi thất bại. Không coi ảnh đã chọn là đã upload.
5. Chat dùng STOMP: CONNECT kèm `Authorization: Bearer ...`; SUB `/user/queue/messages`, `/topic/conv.{id}.typing`; SEND `/app/chat.send`, `/app/chat.read`, `/app/chat.typing`. Cần reconnect, chống tin trùng và đồng bộ lại lịch sử.
6. Cấu hình Android: quyền Internet bản release, quyền camera/micro khi dùng, thông báo theo phiên bản Android; kiểm tra thiết bị thật và build APK release.

Chưa cần thêm nhiều thư viện trước khi chốt kiến trúc. Có thể chọn một giải pháp quản lý trạng thái, một HTTP client, routing và secure storage phù hợp; sau đó bổ sung camera/media, STOMP và Firebase theo từng giai đoạn.

## 10. Thứ tự thực hiện và tiêu chí nghiệm thu

1. **Nền tảng:** theme tiếng Việt, điều hướng, error/loading, cấu hình API, repository dữ liệu giả. Dùng tài khoản thầy cấp; kiểm chứng login và DTO.
2. **Luồng đặc trưng đề tài:** login → môn đang học → soạn/xem lại/gửi bộ câu hỏi → đề xuất của tôi → chi tiết/sửa/xóa theo quyền. Kiểm tra dữ liệu còn nguyên khi lỗi mạng.
3. **Mạng xã hội:** bảng tin, bài viết, upload ảnh, like, bình luận, tìm kiếm. Refresh/tải thêm không trùng bản ghi; lỗi khi đang thao tác phải khôi phục UI hợp lý.
4. **Tương tác học tập và cộng đồng:** luyện tập/đánh giá, hồ sơ, bạn bè/follow/block, thông báo và chat 1–1. Kiểm tra bằng hai tài khoản trên hai máy thật.
5. **Hoàn thiện:** camera/video, push, cache, mất mạng/khôi phục, vòng đời app, token hết hạn, quyền bị từ chối, APK và kịch bản bảo vệ; thêm minigame khi chức năng chính ổn định.

Một màn hình chỉ được coi là tích hợp xong khi chạy đúng API thật, xử lý quyền và lỗi, không mất dữ liệu khi thất bại. Mock giúp phát triển giao diện nhưng phải ghi rõ trong demo và không tính là tích hợp backend.

Các tình huống cần kiểm tra khi triển khai: input sai trong lúc offline; mất mạng giữa upload và nộp; không có môn đang học; phiên đã đổi trạng thái khi đang sửa; token hết hạn ở nhiều request; dữ liệu null/thiếu trường; hết trang; chặn người đang chat; reconnect gây tin trùng; tài khoản đổi trên thiết bị; thông báo mở đúng bài/câu hỏi/hội thoại.

Điểm bắt đầu đề xuất: hoàn thành luồng **đăng nhập → đề xuất câu hỏi → theo dõi đề xuất**, đồng thời xây dựng giao diện bảng tin làm khung cho các tính năng xã hội.
