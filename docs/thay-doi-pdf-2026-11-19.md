# Rà soát PDF mới ngày 19/11/2026

**Trạng thái code mới nhất: xem mục “Hoàn thiện và kiểm tra ngày 22/11/2026” cuối tài liệu.** Các kết luận “chưa có xóa/thu hồi tin nhắn” ở lượt 20/11 là phát hiện trước khi bổ sung, không còn là hiện trạng code.

**Điều chỉnh phạm vi ngày 22/11:** đã gỡ giao diện chọn ID/liên kết tin và thao tác bỏ bản cục bộ do AI tự thêm ngoài PDF. Chạm trạng thái chưa xác nhận chỉ tải lại lịch sử, không mở công cụ đối soát và không gửi lại. Các mô tả “đối chiếu thủ công” ở các đợt dưới là lịch sử đã bị thay thế; không khôi phục tính năng này. Việc gỡ giao diện không được coi là đã giải quyết hạn chế xác nhận tự động của giao thức chat.

**Đã có đợt cập nhật code tiếp sau phần rà soát ban đầu.** Xem mục “Code đã cập nhật” ở cuối tài liệu để biết trạng thái mới nhất. Các mục phát hiện phía trên mô tả thời điểm trước khi sửa.

Nguồn: `C:\Users\ThinkPad\Downloads\Social Network for Student-Generated Question Bank.pptx (2).pdf` (207 trang), đã lưu vào [PDF hiện hành trong repository](<Social Network for Student-Generated Question Bank-2026-11-19.pdf>), so với `docs/Social Network for Student-Generated Question Bank.pptx.pdf` (208 trang). Số trang dưới đây là vị trí trang trong PDF mới, bắt đầu từ 1.

Đây là kết quả đọc tài liệu, không phải xác nhận các luồng đã được nghiệm thu. Lượt này không sửa code ứng dụng hoặc tự đổi các quyết định phạm vi của người dùng. Các chỉ dẫn trong PDF được xem là yêu cầu bài tập cần đối chiếu, không thay thế chỉ dẫn trực tiếp của người dùng.

## Các thay đổi ảnh hưởng frontend

| Trang mới | Nội dung mới so với bản cũ | Ảnh hưởng tới app |
| --- | --- | --- |
| 23 | Bỏ câu giới hạn “bốn hình ảnh HOẶC một video”; thay bằng không giới hạn số ảnh nhưng khi chấm BTL chỉ đăng tối đa bốn ảnh. | Không tự mở chọn ảnh vô hạn: trang 27 vẫn ghi tối đa 4 ảnh khi đăng bài cá nhân. Trong phạm vi chấm giữ 4 ảnh; ghi nhận hai cách diễn đạt trong cùng PDF. |
| 27 | Bỏ giới hạn upload video 10 MB/1–10 giây và câu cấm trộn ảnh/video; thêm chú thích giảng viên vẫn đăng video nội dung học được. | Video giảng viên vẫn cần xem được. Yêu cầu sinh viên đăng video không còn được nêu ở phần nghiệp vụ cập nhật; không coi việc bỏ một giới hạn là cho phép upload video vô hạn. |
| 28 | Bỏ quay video trong app và chọn video từ máy; giữ chụp/chọn ảnh. | Code hiện vẫn có “Chọn video” và “Quay video” trong màn soạn bài. Đây là phần cần điều chỉnh nếu áp dụng phạm vi PDF mới; giữ trình phát video cho bài giảng. Không xóa dữ liệu/draft cũ chỉ để ẩn chức năng. |
| 26 | Làm rõ tùy chọn âm thanh push áp dụng với IT4788. | Phần tùy chọn âm thanh vẫn liên quan trực tiếp bài tập. Trang 29 vẫn yêu cầu âm mặc định hoặc giọng nói do sinh viên thu. |
| 35 | Bỏ dấu “(?)” sau câu cache chỉ áp dụng cho trang chủ. | Câu này rõ ràng hơn bản cũ. Người dùng đã yêu cầu thêm cache thông báo/tin nhắn và xử lý offline, nên không tự xóa các phần đó; đây là yêu cầu bổ sung riêng, không được gán thành yêu cầu nguyên văn PDF. |
| 65 | Bỏ slide danh sách API nhóm chat; chuyển danh sách thông báo lên và bổ sung `notifications/read-all`. | Phù hợp việc giữ chat 1–1, không khôi phục tạo nhóm. Đọc tất cả thông báo đã có trong app. |
| 97 | Danh sách câu hỏi của người dùng được nhóm thành `session_code`, `session_content`, `questions[]`, thay cho từng câu hỏi phẳng. | Khi tích hợp dữ liệu này phải đối chiếu endpoint/schema Swagger thực tế, không chỉ sửa parser theo slide. |

Phần lớn các trang sau danh sách API bị dịch số trang do bỏ slide, không phải mọi trang đều đổi nghiệp vụ. Có bổ sung một slide `GET /exams/{examId}` (trang 128), bỏ slide liệt kê API quản lý hội thoại ở đoạn cũ, đổi một số đường dẫn minigame/report và đánh lại số thứ tự. AI/minigame/sinh đề phía giảng viên vẫn ngoài phạm vi đã chốt. Trang 45 bổ sung trích dẫn nghiên cứu, không phát sinh công việc frontend.

## Những yêu cầu quan trọng vẫn giữ

- Trang 6 ghi rõ **Push Notification: Firebase Cloud Messaging (FCM)** trong tech stack khuyến nghị. Đây không phải chi tiết mới; bản cũ đã có. Swagger hiện tại cũng mô tả `fid` là Firebase Installation ID dùng cho push. Nhóm chưa có cấu hình Firebase từ thầy, nên chưa nghiệm thu nhận push.
- Trang 18 yêu cầu ít nhất hai điện thoại thật, kết nối 3G/4G, chia sẻ màn hình qua USB để thử ngắt mạng; emulator không đủ.
- Trang 23–29 giữ PUBLIC, 500 từ cho bài/bình luận, chỉ Like, không tạo nhóm/tag/ảnh động, ảnh tối đa 4 MB, không sửa bình luận và không tự xóa tài khoản.
- Trang 70–72 vẫn ghi thầy tạo tài khoản vào đầu kỳ; không mở lại luồng đăng ký đã loại khỏi phạm vi.
- Trang 29 vẫn yêu cầu tìm bài ở trang chủ theo từ khóa đảo thứ tự; kiểm chứng khả năng tìm kiếm cần dữ liệu/server thật.
- Trang 35–37 giữ validate trước mạng, loading/lỗi, bảo vệ dữ liệu riêng tư, màu tập trung và kích thước bộ cài.

## PDF chưa đồng bộ hoàn toàn với Swagger

Không sao chép các bảng API trong PDF vào code mà bỏ kiểm tra Swagger. Ví dụ:

- Trang 63 ghi `GET /conversations/direct`, nhưng trang 182 của chính PDF và Swagger dùng **POST** để mở/tạo hội thoại trực tiếp.
- PDF vẫn liệt kê `/auth/login`, trong khi Swagger ngày 19/11 có luồng Android chuẩn `/auth/native/login`, `/auth/native/refresh`, `/auth/native/logout`; nhánh cũ đang được hỗ trợ tương thích tạm thời theo banner Swagger. Code hiện vẫn dùng nhánh cũ.
- Các bảng push trong PDF còn dùng chuỗi cho boolean, còn Swagger dùng boolean thật. Không đổi mapping đúng Swagger về chuỗi.

Ưu tiên điều chỉnh tiếp: luồng auth native theo Swagger; phạm vi soạn bài chỉ ảnh theo phần nghiệp vụ mới; tiếp tục giữ xem video giảng viên. Cấu hình/kiểm thử push vẫn chờ phía thầy. Không suy ra hoàn thành 70% hay đủ điểm tối đa từ số test hoặc số endpoint.

## Kiểm tra code hiện tại sau khi đọc PDF mới

Kết luận: đã có các nhóm chức năng chính trong phạm vi Android frontend, nhưng **chưa đủ để xác nhận hoàn thành/khớp toàn bộ hợp đồng mới**.

| Ưu tiên | Phát hiện trong code | Ảnh hưởng |
| --- | --- | --- |
| Cao | `auth_repository.dart` vẫn dùng ba endpoint auth cũ. Decoder yêu cầu cả access/refresh token, chưa phân loại `ONBOARDING` / `account_state`. | Nhánh đăng nhập phụ thuộc chế độ tương thích server. Tài khoản chưa ACTIVE không thể được coi như đăng nhập đầy đủ; cần xử lý thông báo/trạng thái phù hợp với phạm vi tài khoản thầy cấp, không tự mở đăng ký. |
| Cao | `_mergeMessage` trong `chat_detail_controller.dart` ghép theo ID server hoặc `clientMsgId`; tin cục bộ chưa có ID server, còn `sendStompMessage` không gửi mã cục bộ vì schema không khai báo. | Với broadcast chỉ có ID server, tin đã xác nhận được thêm riêng, còn bản cục bộ có thể chuyển thành `unconfirmed` sau 15 giây. Đây là khoảng trống đối soát thực tế trong code, không chỉ là kịch bản timeout. Cần giải quyết theo cơ chế xác nhận server hỗ trợ; không đoán ghép bằng nội dung hoặc tự replay để che lỗi. |
| Chờ bên ngoài | `PushConfig.configured` cần bốn giá trị cấu hình; chưa có cấu hình project từ thầy. | Mã push đã có nhưng không chạy trong bản thiếu cấu hình, không đủ nghiệm thu push/âm thanh nền. |
| Cần hoàn thiện | Target QUESTION chỉ mở tab ngân hàng; SESSION luôn mở chi tiết đề xuất của mình. | Chưa mở được đúng mọi nội dung đích. Cần xác minh dữ liệu target và quyền bằng server; không giả định mọi phiên đều của tài khoản hiện tại. |
| Điều chỉnh phạm vi | Màn soạn bài còn “Chọn video”, “Quay video” và mô tả giới hạn video cũ. | Chưa cập nhật theo phần nghiệp vụ PDF mới. Bỏ yêu cầu upload video không đồng nghĩa bỏ xem video giảng viên. |
| Cần nghiệm thu | Chưa có kết quả hai điện thoại thật với bản code cuối, push, camera/thu âm và toàn bộ kịch bản mạng. | Chưa đáp ứng bằng chứng bảo vệ tại trang 18 chỉ qua emulator/test giả. |

Đã có code: đăng nhập/lưu phiên/đổi mật khẩu; bảng tin và bài/bình luận/Like/báo cáo; tìm bài; hồ sơ/bạn bè/chặn; đề xuất/sửa/xóa/theo dõi/luyện tập/đánh giá câu hỏi; chat 1–1 và danh sách thông báo/cài đặt. “Có code” không đồng nghĩa mọi nhánh đã hoạt động đúng với server.

Danh sách câu hỏi theo người dùng trong PDF trang 97 chưa có luồng tương ứng trong hồ sơ; app hiện dùng kho luyện tập theo phiên `sessions/practice-catalog`. Chưa coi hai luồng là tương đương nghiệp vụ hay tự thêm API không có trong Swagger đã tải.

Kết quả kiểm chứng gần nhất vẫn là **194 test đạt, analyze sạch, debug/release build thành công** trong log `completeness-*`. Lượt đánh giá này không thay đổi source Dart, không chạy lại test/build đã đạt khi chưa có thay đổi; các test trước đó chưa chứng minh tương thích luồng auth native mới hoặc giải quyết khoảng trống đối soát chat nêu trên. Không chạy thao tác ghi lên server trong lượt này.

## Code đã cập nhật

Theo yêu cầu cập nhật tiếp sau đợt rà soát:

- Login mới dùng `auth/native/login` với ANDROID và UUID ổn định. Refresh/logout phiên mới dùng đúng kênh native. Phiên lưu cũ được nhận diện bằng metadata `native_auth` trong secure storage: thiếu metadata là legacy, refresh/logout ở endpoint cũ, không đổi kênh của token đã phát hành. Server từ chối phiên cũ thì về đăng nhập; không tự chuyển token sang endpoint khác hoặc replay. Không ảnh hưởng mở cache offline chỉ vì cập nhật app.
- Phân loại `account_state` và `token_type` khi login. ONBOARDING/thiếu thiết lập không được lưu/mở bảng tin như phiên đầy đủ. Với tài khoản thầy cấp nhưng chưa ACTIVE, hiển thị yêu cầu liên hệ giảng viên; **không triển khai thêm OTP/admin hoặc màn thiết lập tài khoản mới** trong đợt này. Nếu thầy yêu cầu sinh viên tự hoàn tất mật khẩu ban đầu trên app, cần chốt riêng luồng ONBOARDING đó.
- Bỏ nút chọn/quay video và picker video của màn soạn bài. Chỉ nhận ảnh tĩnh; kiểm tra signature bytes, codec, kích thước. Từ chối video đổi đuôi ảnh trước khi decode/copy/gửi mạng. API tạo bài cũng từ chối media VIDEO. Giữ trình phát video và danh sách video bài giảng. Bài video có sẵn có thể sửa nội dung mà không tự xóa video.
- Giữ nguyên văn bản/tệp trong draft cũ có video; submit dừng trước mạng và hướng dẫn gỡ video. Không tự xóa file nháp để ép đổi phạm vi.
- SESSION notification thử GET chi tiết đề xuất của mình; chỉ khi 403/404 mới kiểm tra GET câu hỏi của phiên công khai và mở luyện tập. Có loading/lỗi/thử lại; không thử luồng khác khi timeout. Cache bảo mật đúng user được dùng khi lỗi mạng, không dùng lại cache đã bị server từ chối quyền. Response tài khoản cũ không mở nội dung dưới tài khoản mới.
- Với chat, bổ sung đối chiếu thủ công: tải lịch sử, người dùng chọn đúng ID tin đã xác nhận của chính mình để liên kết bản cục bộ. Không tự ghép theo nội dung/thời gian và không có request gửi lại. Backend chưa cung cấp mã tương quan gửi/nhận trong Swagger: **xác nhận tự động trọn vẹn vẫn là giới hạn cần làm rõ với backend**; có thể cần thao tác đối chiếu cho tin không có echo ID.
- QUESTION notification vẫn giữ fallback vào ngân hàng vì Swagger không cung cấp lookup theo ID câu hỏi độc lập. Push vẫn chờ cấu hình đúng Firebase project từ thầy; không bật bằng project giả.

So sánh cấu trúc OpenAPI mới với bản 18/11: thêm ba endpoint native; các thay đổi cấu trúc schema/operation khác tìm được thuộc badge, duyệt phiên, upload giảng viên hoặc quản trị ngoài phạm vi hiện tại. Không mở thêm UI chỉ vì có endpoint.

Các kiểm thử mới bao gồm kênh auth/token lưu cũ, ONBOARDING không lọt vào shell, SESSION riêng/công khai/lỗi mạng/cache/quyền/đổi user, video giả đuôi ảnh, bảo toàn draft video cũ và đối chiếu chat theo ID người dùng chọn. **203 test đạt** (`.dart_tool/update-19-tests.log`), `flutter analyze --no-pub` sạch (`.dart_tool/update-19-analyze.log`). Kiểm thử widget cũng xác nhận màn soạn bài không còn nút chọn/quay video. Không dùng các kết quả mock để tuyên bố đã thử nghiệp vụ trên server hoặc điện thoại vật lý.

Build bản cuối thành công: debug x86_64 (191 giây) và release ARM64 khoảng **22,2 MB** (119,8 giây), tại `build/app/outputs/flutter-apk/app-debug.apk` và `app-release.apk`. Log `.dart_tool/update-19-debug.log`, `.dart_tool/update-19-release.log`. Release giữ cách ký debug hiện có phục vụ bài tập. Chưa cài/chạy lại APK cuối trên thiết bị thật trong đợt cập nhật này; không gửi thao tác ghi nghiệp vụ lên server để thử.

## Rà soát độ đầy đủ ngày 20/11/2026

Đã tải lại OpenAPI vào `.dart_tool/swagger-2026-11-20.json`. So với bản 19/11, không thêm/bớt path hoặc thay đổi cấu trúc schema/operation khi loại phần mô tả/ví dụ khỏi phép so sánh. Không suy ra server triển khai và dữ liệu thật không thay đổi từ kết quả này.

| Nhóm | Hiện trạng frontend |
| --- | --- |
| Auth | Có login native, lưu/khôi phục phiên, refresh, logout, đổi mật khẩu; nhận diện phiên legacy và tài khoản chưa ACTIVE. ONBOARDING chỉ được thông báo liên hệ giảng viên, không có luồng tự hoàn tất thiết lập. |
| Bài viết/bảng tin | Có tải/refresh/phân trang/cache; soạn/sửa/xóa bài, 4 ảnh tĩnh, chụp/chọn ảnh, xem ảnh/video bài giảng, Like/bình luận/báo cáo, tìm bài. |
| Hồ sơ/quan hệ | Có xem/sửa hồ sơ, xem ảnh đại diện/bìa, tìm người, danh sách bạn/lời mời/follow/chặn/bỏ chặn. |
| Ngân hàng câu hỏi | Có chọn lớp học phần, nộp/sửa/xóa/theo dõi đề xuất, kho luyện tập theo phiên, trả lời, đánh giá 0–4, xem đánh giá và báo lỗi. Không có màn thống kê riêng qua `questions/{id}/statistics`; sự có mặt trong bảng API không tự chứng minh phải thêm màn mới. Luồng xem câu hỏi theo từng người ở PDF trang 97 vẫn chưa có, còn Swagger hiện không có endpoint đó để tích hợp trực tiếp. |
| Chat | Có hội thoại 1–1, text/ảnh/emote, lịch sử/phân trang/cache, typing/read receipt và đối chiếu thủ công tin chưa xác nhận. **Chưa có thao tác xóa/thu hồi tin gửi lên server** mặc dù PDF trang 185 và Swagger đều mô tả `DELETE /messages/{id}` với scope ME/EVERYONE. Nhận sự kiện MESSAGE_REVOKED không thay thế chức năng chủ động xóa/thu hồi. Đây là phần thiếu cần bổ sung nếu bao phủ các thao tác chat trong PDF mới. |
| Thông báo/cài đặt | Có danh sách/lọc/phân trang/cache, đọc từng mục/tất cả, cài đặt API và thu âm/nghe thử cục bộ. SESSION được phân quyền trước khi mở; QUESTION còn fallback. Push chờ cấu hình Firebase. |

Không kết luận đủ hoàn thành: còn thao tác xóa/thu hồi chat; push chưa có cấu hình; xác nhận gửi chat tự động chưa có cơ chế tương quan được tài liệu bảo đảm; QUESTION chưa mở đúng chi tiết; chưa nghiệm thu hai máy thật/mạng/media. Những phần đã loại rõ khỏi phạm vi (đăng ký/OTP/reset do thầy xử lý, iOS, nhóm/GIF, admin/AI/minigame, lịch sử tìm kiếm) không tính là thiếu trong phạm vi người dùng đã chốt. Chưa có căn cứ tính tỷ lệ 70% hoặc cam kết điểm chấm.

Lượt 20/11 chỉ đọc/đối chiếu và cập nhật báo cáo, không sửa source Dart hoặc gọi API ghi. Kết quả tự động gần nhất vẫn là 203 test/analyze/build ngày 19/11; không chạy lại bộ kiểm tra đã đạt khi chưa có thay đổi source.

## Hoàn thiện và kiểm tra ngày 22/11/2026

### Phần đã bổ sung/sửa

- Nhấn giữ tin đã được server xác nhận để **Xóa ở phía tôi** hoặc **Thu hồi với mọi người**. Chỉ tin của chính mình có lựa chọn thu hồi. Có bước xác nhận và loading; không xóa trước server, không hiển thị thành công từ việc gửi request đơn thuần.
- Gọi `DELETE /messages/{id}` với JSON `scope: ME | EVERYONE`; kiểm tra response đúng `message_id` và `scope`. Không thêm sửa/reaction/trả lời tin hoặc các API nhóm ngoài phạm vi.
- Nếu kết quả DELETE chưa rõ, lưu dấu thao tác trong `DraftStore` theo tài khoản và không replay. Chỉ GET khởi chạy sau thao tác mới được dùng để kiểm tra kết quả. Không suy vắng mặt trên một trang phân trang là đã xóa toàn bộ; không lộ kết quả tài khoản cũ sau đổi phiên.
- Chặn dữ liệu đã xóa xuất hiện trở lại qua GET cũ, load-more hoặc sự kiện lặp. Đọc cờ `MessageDto.revoked`, loại nội dung/media thu hồi khỏi timeline/cache. Dữ liệu tin nhắn sai kiểu được xử lý bằng trạng thái lỗi thay vì làm vỡ callback socket.
- Đồng bộ dòng xem trước hội thoại khi xóa, kể cả refresh danh sách thất bại do offline. Có sự kiện nội bộ chỉ trong feature chat, tách theo user và dispose subscription; không sửa router/theme/core. Repo cũng làm sạch preview cache khi mở chat trực tiếp mà không có màn danh sách đang chạy.
- Đã gỡ công cụ chọn ID/ghép/bỏ bản cục bộ ngoài PDF. Không đưa lại công cụ này dưới tên tính năng kiểm thử.

### Độ đầy đủ trong phạm vi đã chốt

| Nhóm | Code hiện có | Điểm còn phải kiểm chứng/giới hạn |
| --- | --- | --- |
| Tài khoản | Login native, cặp token/kênh phiên, khôi phục offline, refresh/logout, đổi mật khẩu | Tài khoản thầy cấp cần ACTIVE; app thông báo liên hệ giảng viên khi nhận ONBOARDING, không tự mở OTP/admin/reset. |
| Bảng tin/bài viết | Phân trang/refresh/cache, tìm bài, đăng/sửa/xóa, Like/bình luận/báo cáo, chụp/chọn 4 ảnh tĩnh, xem ảnh và video giảng viên | Thứ tự ưu tiên bạn bè và tìm toàn văn/đảo từ thuộc xử lý server; cần dữ liệu thật để kiểm chứng. |
| Hồ sơ/quan hệ | Xem/sửa hồ sơ, viewer ảnh, tìm người, bạn bè/lời mời/follow/chặn/bỏ chặn | Cần thử hai tài khoản để xác nhận quyền cả hai chiều và các thay đổi đồng thời trên server. |
| Ngân hàng câu hỏi | Lớp học phần đang học, đề xuất tối thiểu 3 câu theo schema, nguồn gốc, sửa/xóa/theo dõi, luyện tập/trả lời/đánh giá 0–4/báo lỗi | Không tự thêm màn/endpoint theo bảng API PDF khi Swagger không có; kho luyện tập theo phiên không được gọi là đã có danh sách câu hỏi theo từng người. |
| Chat 1–1 | Text/ảnh/emote, lịch sử/cache/nháp, typing/read receipt, xóa/thu hồi hai scope | Luồng gửi có thể còn bản chưa xác nhận nếu server không trả mã tương quan; đây là hạn chế tích hợp cần kiểm chứng, không phải tính năng mới trong PDF. Không báo “Đã gửi” giả hoặc tự ghép theo nội dung. |
| Thông báo/cài đặt | Danh sách/lọc/phân trang/cache, đọc từng mục/tất cả đúng response server, SESSION theo quyền, boolean cài đặt, thu âm/nghe thử | QUESTION còn vào ngân hàng vì target chưa có session ID/lookup trực tiếp. Push chưa nhận thật vì chưa có cấu hình Firebase project của thầy. |
| Offline/vòng đời | Validate trước mạng, giữ cache/input/nháp, timeout, không replay ghi, giới hạn tài nguyên, session và dữ liệu theo user | Mock kiểm tra được các nhánh đã nêu nhưng chưa thay thế thử chế độ máy bay, Wi-Fi/4G, process death, quyền và media trên điện thoại vật lý. |

Đăng ký/OTP/reset do thầy xử lý; iOS, backend/admin/AI/minigame; nhóm/GIF/tag/reaction ngoài Like; lịch sử tìm kiếm và công cụ đối chiếu ID đều không được tự bổ sung. Sự kiện huy hiệu hoặc bài có `SQB_SEED` do API bảng tin cung cấp không đồng nghĩa app tự thêm minigame hoặc dữ liệu giả.

### Kiểm chứng

**213 test đạt**, analyze sạch. Log `.dart_tool/complete-22-tests.log`, `.dart_tool/complete-22-analyze.log`; kiểm thử bổ sung cho xác nhận DELETE, bấm lặp, quyền thu hồi, timeout/lưu marker qua mở lại, phân trang, dữ liệu cũ, preview offline/tách tài khoản và cờ revoked. Không gọi API ghi nghiệp vụ hay gửi tin tới người khác trong đợt này.

Swagger tải lại ngày 22/11 tại `.dart_tool/swagger-2026-11-22.json`: thay đổi cấu trúc so với 20/11 thuộc reset tài khoản quản trị, xuất đề và các schema nhập/cấp tài khoản. Không mở thêm chức năng frontend ngoài phạm vi vì những thay đổi đó. PDF hiện hành vẫn là bản 207 trang đã lưu trong repository, có tính đến chữ đỏ/chú thích thầy xử lý thay.

Chưa thể xác nhận “đủ nghiệm thu”: còn cấu hình/payload push, điều hướng chi tiết QUESTION, kiểm chứng gửi/nhận chat thực tế và bộ kịch bản trên hai điện thoại thật. Không tính tỷ lệ hoàn thành/điểm chấm dựa trên số test.

APK bản cuối 22/11 đã build thành công sau sửa phân trang/preview: debug x86_64 (34,6 giây) và release ARM64 khoảng 22,2 MB (77,7 giây), log `.dart_tool/complete-22-debug.log`, `.dart_tool/complete-22-release.log`. Giữ cấu hình ký debug hiện có cho bài tập; không coi build thành công là nghiệm thu native/storage/media. File tại `build/app/outputs/flutter-apk/app-debug.apk` và `app-release.apk`. Chưa cài/chạy lại bản cuối trên điện thoại thật trong đợt này.
