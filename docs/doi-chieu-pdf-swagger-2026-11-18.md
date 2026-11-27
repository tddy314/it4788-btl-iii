# Đối chiếu PDF, Swagger và ứng dụng Android

> Đây là đối chiếu bản PDF/Swagger trước ngày 19/11. Xem [cập nhật 19/11](thay-doi-pdf-2026-11-19.md) cho auth native, phạm vi bài chỉ ảnh và điều hướng SESSION; các kết luận cũ tương ứng được thay bằng bản cập nhật.

Đối chiếu lại theo yêu cầu ngày 18/11/2026. Phạm vi vẫn là frontend Android tích hợp backend của thầy. Tài liệu này bổ sung và thay các kết luận liên quan trong [bàn giao 17/11](hoan-thien-luong-2026-11-17.md).

Nguồn trực tiếp: [PDF 208 trang](<Social Network for Student-Generated Question Bank.pptx.pdf>), [OpenAPI JSON](https://snsqb.duckdns.org/api/v1/docs/openapi.json), code và kiểm thử trong repository. Đã tải lại OpenAPI; nội dung giống bản tải ở đợt sửa 17/11. Tài liệu kế hoạch/backlog do nhóm hoặc AI viết không phải yêu cầu nguyên văn của giảng viên.

## Thông báo đã đọc và tạo nhóm

- **PDF trang 196** mô tả `POST /notifications/{id}/read`, trả ID, `is_read`, `read_at`, `unread_count`. **Swagger hiện tại** dùng tên `read` thay `is_read`, ID/count là số, thời gian ISO. App dùng tên hiện tại, chấp nhận tên cũ khi đọc response; gửi ID số hợp lệ trong đường dẫn, không gửi body ngoài schema.
- PDF không nói bắt buộc optimistic update. Chờ server xác nhận là lựa chọn triển khai nhằm không báo đọc thành công khi mất mạng. Mục Optimistic Update trong backlog cũ là đề xuất nội bộ. Lỗi trước đây là bỏ qua response rồi tự giảm số đếm; đã sửa dùng đúng số đếm/thời gian server, kiểm tra response đúng ID và `read: true`.
- Khi chạm một thông báo đang hiện trong lúc refresh, vẫn gửi thao tác đọc một lần; GET cũ không được ghi đè kết quả. Khi timeout, chỉ tải lại bằng GET để đối soát. `POST /notifications/read-all` trả `data: null`, không ép nó phải có payload như đọc từng mục.
- **PDF trang 25:** “Hiện tại chưa cho phép tiến hành lập nhóm nhiều người cùng chat.” **Trang 27:** “Không có việc tham gia và tạo lập nhóm.” Vì vậy bỏ nút tạo nhóm và từ chối mở hội thoại GROUP. Swagger có API nhóm để phục vụ hệ thống rộng hơn; sự tồn tại của API không làm thay đổi giới hạn PDF. Đã xóa widget tạo nhóm, picker GIF và helper tạo nhóm không còn sử dụng để không để lại chức năng ngoài phạm vi.

## Bảng rà soát trong phạm vi đã chốt

“Đã đối chiếu” dưới đây nghĩa là đã đọc yêu cầu, mapping trong code và kiểm thử liên quan. Không đồng nghĩa đã thử mọi nhánh với server thật hoặc thầy đã nghiệm thu.

| Mảng | Căn cứ PDF / Swagger | Kết quả code và giới hạn |
| --- | --- | --- |
| Đăng nhập | PDF 23; `auth/login`, `auth/refresh` | Dùng email/tài khoản được cấp, platform ANDROID, UUID thiết bị, cặp token; không thêm danh sách nhiều tài khoản ở màn login. Không làm đăng ký theo yêu cầu riêng của người dùng. |
| Đổi mật khẩu/đăng xuất | PDF 23; `auth/change-password`, `auth/logout` | Đúng method/body, giữ mật khẩu hiện tại nguyên trạng, phân biệt lỗi phiên với lỗi mạng; local logout không phụ thuộc server đang online. Mật khẩu mới chỉ gồm chữ/số theo PDF, validate trước mạng; Swagger không định nghĩa pattern nên ví dụ chứa ký tự đặc biệt không được dùng để thay yêu cầu này. Không áp chính sách mật khẩu mới để sửa hay chặn mật khẩu đăng nhập đã được thầy cấp. Không tự thêm độ dài tối thiểu chưa được tài liệu quy định. |
| Bài viết public | PDF 23–27; `posts`, `posts/{id}` | Gửi PUBLIC, chỉ Like, tối đa 500 từ; không mở reaction/privacy khác dù API có hỗ trợ. Có sửa/xóa bài; sau thao tác được xác nhận điều hướng theo luồng hiện tại. |
| Media bài viết | PDF 23, 27–28; `medias/upload?purpose=POST` | Tối đa 4 ảnh hoặc 1 video, không trộn; ảnh 4 MiB; video 10 MiB/1–10 giây. Camera và chọn file, kiểm tra bytes/codec/thời lượng; ảnh động bị từ chối. Giới hạn dùng MiB theo mã hiện tại, PDF chỉ ghi MB không định nghĩa quy đổi; ranh giới dung lượng cần đối chiếu server khi nghiệm thu. |
| Bình luận | PDF 23, 25–26; `comments` | Chỉ text/link/emote, 500 từ, không reaction, không sửa, không cho chủ bài xóa bình luận người khác; chỉ chủ bình luận có lối xóa. Không gửi ảnh bình luận chỉ vì Swagger có `media_url`. |
| Hiển thị bài dài / xem ảnh | PDF 27–28 | “Xem thêm” mở rộng một chiều, không có nút thu gọn. Ảnh crop ở trung tâm; có viewer ảnh/video. Đã nối ảnh đại diện và ảnh bìa vào trình xem ảnh phóng to dùng chung. Trải nghiệm/animation giống Facebook vẫn cần đánh giá trực quan trên máy thật. |
| Bảng tin | PDF 25, 35–36; `activity-feeds`, `new-count` | Dùng thứ tự server, không tự sắp xếp làm sai phân trang. Giữ cache public, refresh/tải thêm, loại nội dung bị 403/404; backend quyết định ưu tiên bạn bè/thứ tự thời gian, client không thể bảo đảm thuật toán server chỉ bằng unit test. |
| Tìm bài từ trang chủ | PDF 29; `GET search` | Đã bổ sung nút Tìm bài viết và `features/search`: `type=POST`, query, `after` là offset, limit 20. Debounce, bỏ kết quả cũ, giữ kết quả cùng từ khóa khi lỗi, xóa khi đổi query/tài khoản. Mở kết quả phải GET lại chi tiết để kiểm tra quyền/xóa bài. Không giả lập tìm từ đảo thứ tự ở client; cần xác nhận Elasticsearch/server bằng dữ liệu thật. |
| Hồ sơ/bạn bè/chặn | PDF 24; `users/me`, `users/{id}`, `friendships`, `follows`, `blocks` | Đã đọc DTO/method và các kiểm thử quan hệ/quyền/đổi tài khoản. Xác nhận chặn cập nhật bảng tin/cache; bỏ chặn không tự khôi phục bạn bè. Server phải chặn cả hai chiều truy cập/tin nhắn. |
| Đề xuất câu hỏi | PDF 30, 32; `sessions/propose`, `my-submissions` | Tạo bằng lớp học phần đang học, tối thiểu 3 câu theo schema. Tạo dùng `llm_generated`, sửa dùng `source`; sửa/xóa chỉ khi server cho phép. RESOLVED là đã xử lý, không suy tất cả câu được duyệt. Nguồn AI/tự làm không xuất hiện ở card công khai; backend phải thực thi việc ẩn với giảng viên. |
| Luyện tập/đánh giá | `sessions/{id}/questions`, `questions/{id}/answer`, `/rate`, `/ratings`, `/report` | Dùng phiên bản câu hỏi, kết quả chấm server; thang 0–4, chấp nhận 0. Không suy đáp án đúng khi server ẩn. Rating comment/report có giới hạn ký tự riêng theo schema, không nhầm với bình luận bài 500 từ. |
| Chat 1–1 | PDF 25, 28, 32, 180–193; `conversations/direct`, `/messages`, STOMP | Chỉ DIRECT, bỏ lối gửi GIF và kiểm tra ảnh tĩnh bằng codec trước copy/upload; thêm từ chối ảnh động hồ sơ. Gửi typing theo Swagger là `typing`/Boolean ở `/app/chat.typing`, nhận sự kiện qua private queue; PDF cũ dùng `is_typing`/topic riêng. Có đọc cả tên trường nhận cũ; không phát cả hai hợp đồng lên server. |
| Phân trang hội thoại | `ConversationListResponseDto`, `LastMessageDto` | Đã sửa dùng `next_cursor` đầy đủ qua query `cursor` khi có; dùng `after` khi không có cursor. Đọc `last_message.message_id`; trường hợp trang lọc hết GROUP vẫn có nút tải thêm. Không hiện spinner vô hạn khi chưa thực sự tải. |
| Đã xem tin nhắn | PDF 192; private queue | Chấp nhận reader ID hoặc object `reader.user_id` theo mô tả cũ; chỉ đánh dấu tin của mình tới ID được đọc. Người gửi tự đọc tin của mình không được tính là đối phương đã xem. |
| Thông báo | PDF 194–197; `notifications` | Danh sách, phân trang, đã đọc/chưa đọc, cache, mở đích; đọc từng mục lấy count/time server. QUESTION không có endpoint GET riêng theo ID trong Swagger; giữ fallback vào Ngân hàng câu hỏi, không giả ID câu hỏi thành ID phiên. Không tuyên bố đã có điều hướng chi tiết mọi câu hỏi khi API chưa cung cấp định danh phiên. |
| Cài đặt/push/giọng nói | PDF 6, 26, 29, 198–201; Swagger `settings/push`, `devices/fid` | Boolean/categories theo Swagger, giữ quiet_hours/key không hiển thị; thu âm tối đa 15 giây và chọn âm cục bộ, không gửi `sound_type` ngoài schema. Có mã client Firebase/FID; không tạo backend mới. Chưa có cấu hình đúng Firebase project của server, chưa thử push hay thu/phát âm thanh native thật. |
| Privacy/cache/nháp | PDF 35; yêu cầu offline bổ sung của người dùng | Feed public/profil public chọn lọc có thể dùng preferences. Nội dung thông báo, chat, cache ngân hàng câu hỏi (nguồn đề xuất/trả lời cá nhân) và nháp dùng secure storage, có namespace user/giới hạn; chuyển cache cũ theo resource khi đọc. Không hứa dữ liệu chỉ có trong RAM sống qua process death. File media nằm trong thư mục riêng app; chưa triển khai mã hóa bổ sung nội dung từng file nháp. |
| Đóng app/độ ổn định | PDF 27, 35–37 | Có nút đóng app Android. Validate trước request, loading/lỗi tiếng Việt, cache/draft, không replay ghi, kiểm tra response muộn/dispose. Độ mượt và các chuyển đổi mạng thực tế cần thử trên điện thoại. |

## Giới hạn phạm vi và nguồn chưa thống nhất

- Các quyết định riêng đã được người dùng chốt vẫn giữ: Android, thầy cấp tài khoản nên bỏ đăng ký, phải đăng nhập mới xem bài; backend/admin/AI do phía hệ thống phụ trách. Không mở lại iOS, admin, thuật toán AI hay minigame chỉ vì PDF mô tả toàn hệ thống. Không cam kết đủ tỷ lệ chức năng/điểm chấm từ số lượng test.
- Swagger hỗ trợ nhiều hơn PDF: nhóm chat, ảnh/sửa bình luận, reaction đa dạng, nhiều quyền hiển thị, xóa tài khoản. Đây không phải căn cứ đưa các chức năng PDF loại trừ vào app.
- Chat gửi xong nhưng mất xác nhận vẫn là `unconfirmed` khi không có ID đối soát. Swagger không khai báo `client_msg_id` trong dữ liệu gửi: đã bỏ trường này khỏi STOMP gửi lên; mã theo dõi vẫn chỉ dùng cục bộ. Backend chưa xác nhận cơ chế echo/chống trùng; không tự replay hoặc đoán xác nhận theo nội dung để ép chuyển thành “Đã gửi”.
- Chuyển cache cũ chỉ xóa bản preferences sau khi ghi bản bảo mật thành công. Nếu storage đang lỗi, giữ bản cũ hợp lệ đúng tài khoản để không mất dữ liệu offline; sẽ thử chuyển lại khi đọc sau. Mọi lần ghi cache mới vẫn đi vào secure storage, không quay lại ghi plaintext để chữa lỗi.
- Push data-only so với notification payload, định danh người nhận và âm thanh chạy nền phải đối chiếu payload thật. Cài SDK không đủ để chứng minh server đang push được.

## Kết luận đủ / thiếu / ngoài phạm vi

Các nhóm chức năng đã có mã frontend và mapping API được liệt kê trong bảng trên. Chưa thể kết luận toàn bộ bài đã đủ nghiệm thu từ việc đọc code hoặc số test đạt.

| Trạng thái | Nội dung và bước còn lại |
| --- | --- |
| Đã sửa thêm trong lần rà soát cuối | Xóa mã nhóm/GIF thừa, bỏ tải ảnh chat ngoài yêu cầu; mở ảnh hồ sơ bằng viewer chung; bỏ nhãn “Trực tuyến” hiển thị cố định khi không có dữ liệu presence; dùng màu từ theme; kiểm tra ID/phiên khi tạo hội thoại và từ chối dữ liệu tìm bạn sai định dạng thay vì giả danh sách rỗng. |
| Chờ cấu hình từ thầy | Người dùng xác nhận **chưa có cấu hình Firebase đúng project của server**. Frontend đã có điểm tích hợp FID nhưng chưa nghiệm thu push, điều hướng từ push hay âm thanh nền. Cần cấu hình client, payload thật và thiết bị nhận. Không xây backend thay thầy. |
| Cần xác minh hợp đồng socket thật | Phải kiểm tra xác nhận gửi/đã xem/đang nhập bằng hai tài khoản và đối soát sau mất phản hồi. Không có bảo đảm chống trùng/echo ID trong tài liệu hiện tại; có thể còn trạng thái chưa xác nhận cần tải lại/đối soát. |
| Điều hướng chưa đủ dữ liệu API | Thông báo QUESTION hiện vào ngân hàng câu hỏi vì không có endpoint GET chi tiết câu hỏi độc lập hoặc ID phiên trong target. SESSION cần thử quyền truy cập với cả phiên của mình và của người khác; không coi route đã đăng ký là bằng chứng mở đúng mọi trường hợp. |
| Cần nghiệm thu thực tế | Chạy toàn bộ nghiệp vụ với server; ngắt mạng trước/trong upload/gửi, khôi phục mạng, đóng/mở process, đổi tài khoản; thử camera, thu/phát giọng nói, quyền và giao diện trên điện thoại vật lý. Kiểm tra tìm toàn văn/đảo từ và ưu tiên bảng tin phía server. |
| Chủ động loại khỏi phạm vi | Đăng ký/OTP và iOS theo quyết định người dùng; backend/admin/AI/minigame theo phân công. Nhóm chat, GIF/ảnh động, tag, reaction ngoài Like, sửa/ảnh/reaction bình luận, danh sách người Like, xóa tài khoản theo giới hạn PDF. Không bổ sung chỉ vì Swagger có endpoint. |

## Kiểm chứng của đợt này

Kiểm tra tự động gồm model/transport theo schema, read receipt khác số đếm cục bộ, refresh đến muộn, cache bảo mật/migration/tách tài khoản, lỗi chuyển cache không xóa bản offline, cursor có cùng timestamp, ảnh động PNG/WebP, truy vấn tìm kiếm đến muộn và màn nhỏ/font lớn. Bổ sung kiểm tra viewer ảnh hồ sơ, trường STOMP gửi đúng schema, ID hội thoại và phiên cũ bị từ chối, dữ liệu tìm bạn sai định dạng. **194 kiểm thử đạt**, `flutter analyze --no-pub` không có lỗi. Kịch bản đổi mật khẩu đã kiểm tra từ chối ký tự đặc biệt không gọi API, rồi đặt mật khẩu hợp lệ và đăng xuất qua stack bảo vệ. Log kết quả cuối: `.dart_tool/completeness-tests.log`, `.dart_tool/completeness-analyze.log`.

Không đăng bài, gửi tin cho người khác hay sửa cấu hình server để tạo tình huống. Chưa chạy lại toàn bộ nghiệp vụ với tài khoản/server thật và hai điện thoại vật lý trong đợt này. Kiểm thử mock/widget không thay thế nghiệm thu đó.

APK cuối cùng build thành công sau các sửa đổi trong báo cáo: debug x86_64 cho emulator (53,6 giây) và release ARM64 khoảng **22,2 MB** cho điện thoại tương thích (100,8 giây). Log: `.dart_tool/completeness-debug.log`, `.dart_tool/completeness-release.log`. Bản release vẫn dùng cấu hình ký debug hiện có phục vụ bài tập. Đã cài và mở một bản debug trước đó trên emulator trong đợt, thấy màn đăng nhập; chưa cài lại bản cuối này để tránh gián đoạn thiết bị người dùng đang sử dụng. Không dùng ảnh màn đăng nhập làm bằng chứng các API nghiệp vụ hay storage native đã được thử hết.

Tạo lại APK tương ứng từ thư mục gốc:

```sh
flutter build apk --debug --target-platform android-x64
flutter build apk --release --target-platform android-arm64
```
