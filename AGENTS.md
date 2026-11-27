# Context cho AI làm việc trong dự án SQB
> Đọc file này trước khi code. Hướng dẫn áp dụng cho toàn repository và từng nhánh feature. Đây là quyết định, quy ước và đặc tả kỹ thuật đã chốt của dự án; yêu cầu mới, rõ ràng của người dùng có thể cập nhật chúng. Kiểm tra code thực tế trước khi sửa vì hiện trạng có thể thay đổi sau mỗi lần merge.

---

## 1. Phạm vi đã chốt với nhóm

- **Bài tập lớn IT4788:** Mạng xã hội cho sinh viên đóng góp câu hỏi vào ngân hàng đề theo môn học; trải nghiệm giao diện và tương tác quen thuộc tương tự Facebook.
- **Nền tảng & Ngôn ngữ:** Flutter, chỉ triển khai Android mobile, toàn bộ giao diện và thông báo người dùng bằng **tiếng Việt**.
- **Phạm vi kỹ thuật:** Nhóm chỉ làm **Frontend** và tích hợp vào hệ thống Backend có sẵn do thầy giáo cung cấp; không triển khai backend, database, thuật toán AI hay trang admin.
- **Tài khoản:** **Thầy cấp tài khoản: không làm đăng ký hoặc OTP kích hoạt từ đăng ký.** Đổi mật khẩu sau đăng nhập là chức năng riêng.
- **Quên mật khẩu:** PDF mới trang 76 ghi chú “ĐỂ ĐƠN GIẢN THÌ THẦY SẼ RESET QUA ĐƠN CỦA SV”. Sinh viên liên hệ/gửi đơn cho thầy; app không triển khai tự reset/quên mật khẩu, OTP khôi phục, form gửi đơn hoặc gọi API reset dành cho admin. Không nhầm với chức năng đổi mật khẩu sau đăng nhập đang có.
- **Đọc cả ghi chú trên slide:** Khi đối chiếu PDF, phải đọc chú thích, chữ đỏ/khung khoanh, dấu sao và phần bổ sung đè lên bảng API; không chỉ đọc tên endpoint hoặc bảng tham số. Các ghi chú thầy xử lý thay/đơn giản hóa giới hạn phạm vi app dù bảng bên dưới hoặc Swagger vẫn có API. Trang 70–72 ghi thầy tạo tài khoản, trang 76 ghi thầy reset theo đơn. Nếu chữ trên ảnh không trích xuất được hoặc phạm vi chú thích không rõ, kiểm tra trực quan trang PDF và ghi nhận điểm cần xác minh, không tự mở thêm feature.
- **Quyền truy cập:** **Phải đăng nhập trước khi vào bảng tin, xem bài và tương tác. Không có chế độ khách (Guest mode).** Mọi API đọc/ghi đều yêu cầu Bearer token.
- **Quản lý phiên:** Khi còn phiên đăng nhập, mất mạng không đồng nghĩa với đăng xuất; có thể xem nội dung đã lưu trên máy.
- **Luồng chính:** Đăng nhập → Chọn môn đang học → Soạn/nộp bộ câu hỏi → Theo dõi đề xuất; bổ sung các tính năng xã hội theo công việc được phân công.
- **Giới hạn nghiệp vụ:** Chỉ triển khai tính năng được giao. Không tự mở rộng sang minigame, AI, chat nhóm, duyệt câu hỏi hay sinh đề cho giảng viên.
- **Không biến xử lý lỗi thành tính năng ngoài PDF:** Không thêm màn/công cụ yêu cầu người dùng đối chiếu ID tin nhắn, ghép bản cục bộ với bản server hoặc quản lý outbox kỹ thuật. Ngày 22/11 đã gỡ luồng đối chiếu thủ công do AI tự thêm. Giữ trạng thái lỗi và tải lại lịch sử phù hợp; không báo thành công giả, tự ghép bằng nội dung hoặc replay tin chưa rõ kết quả. Các ghi chép cũ nói đã có đối chiếu thủ công là lịch sử, không phải yêu cầu cần khôi phục.
- **Tìm kiếm (cập nhật theo yêu cầu đối chiếu PDF ngày 18/11/2026):** Tìm người trong tab Bạn bè dùng `GET search?type=USER`; trang chủ bổ sung tìm bài viết dùng `GET search?type=POST` theo PDF trang 29. Không tự mở thêm tìm kiếm mọi thực thể, lịch sử hay từ khóa thịnh hành. Tìm toàn văn/đảo thứ tự từ là công việc của API, không giả lập kết quả ở client.

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

Danh sách dưới đây là các tình huống nhóm chủ động dự kiến, không phải danh sách thầy đã công bố và không có nghĩa code đã xử lý tất cả. Chọn trường hợp liên quan đến feature, ghi rõ đã chạy hay chưa; không tự mở rộng chức năng để đáp ứng tình huống chưa áp dụng.

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

## 3. Hiện trạng codebase — Cập nhật 23/11/2026

**Số đếm phản hồi 23–24/11:** `CommentsScreen` lấy số phản hồi chưa xóa từ thread khi đã tải đủ; không lấy số mục trang đầu làm tổng khi còn phân trang hoặc chạm giới hạn 200 mục. Thêm/xóa được server xác nhận cập nhật số đếm của đúng bình luận cha, giữ phản hồi đã xác nhận khi refresh lỗi; không giảm số đếm trước xác nhận xóa. Bộ widget test bình luận/bài viết có 23 test đạt, gồm xóa phản hồi cuối 1 → 0, xóa khi còn phân trang, bỏ placeholder đã xóa khỏi tổng và thêm phản hồi khi snapshot cha cũ. **Toàn bộ 229 test đạt, analyze sạch** (`.dart_tool/reply-count-full-tests.log`, `.dart_tool/reply-count-analyze.log`); kết quả 226 test bên dưới là lượt trước bản sửa số đếm. Build debug x86_64 thành công (`.dart_tool/reply-count-build.log`), đã cài đè -r và mở app trên emulator-5554; xác nhận `lastUpdateTime=2026-11-24 00:02:39`. Chưa thử thao tác thêm/xóa trên dữ liệu server thật trong lượt này; không suy nghiệm thu nghiệp vụ từ test giả hoặc việc cài APK.

**Like/bình luận 23/11:** theo yêu cầu người dùng, `PostCard` hiển thị Like/Unlike và số đếm ngay khi bấm, giữ biểu tượng thay spinner, chặn bấm lặp; trạng thái tạm chỉ ở widget, không gọi `onChanged`/ghi cache trước xác nhận. Giữ GET kiểm tra trước POST vì `/react` là toggle; timeout thao tác ghi chỉ cho GET kiểm tra, không replay. Offline đã biết không đổi trạng thái; server từ chối thì hoàn tác, response cũ không tác động thẻ bài khác/tài khoản khác. `CommentsScreen` hiện bản tạm với “Đang gửi… / Gửi thất bại / Chưa xác nhận được”, lưu nháp bảo mật đến khi POST thành công; thay bằng bản có ID server, khử trùng ID và giữ bình luận đã xác nhận nếu refresh lỗi mạng. Không tự ghép bản chưa xác nhận theo text/thời gian hoặc tự gửi lại. Swagger kiểm tra lại 23/11 trong `.dart_tool/optimistic-23-openapi.json`. APK 22/11 bên dưới chưa chứa thay đổi này; cần hot reload/chạy hoặc build lại để thử.

**Cửa sổ bình luận 23/11:** `comments_sheet.dart` mở bottom sheet không modal qua Scaffold, kéo từ 28% đến 88%, ban đầu 62%; phần bài còn lộ vẫn cuộn được. Bảng tin và chi tiết bài đều dùng cửa sổ này qua `PostCard`, không push màn bình luận riêng. Phản hồi tải ngay dưới bình luận cha trong cùng danh sách cuộn; ô nhập chỉ rõ người đang được trả lời. Giữ nguyên `parent_comment_id`, chuyển mục tiêu sau khi lưu nháp, capture tên record trước khi đưa vào hàng đợi ghi để không lưu nhầm nháp gốc/phản hồi. Kiểm tra timeout theo đúng thread, không tự gửi lại. Đóng bằng nút, kéo hoặc Back; giữ nháp và cập nhật số đếm từ server khi đóng.

**Kiểm chứng 23/11 mới nhất:** **226 test đạt, analyze sạch**, log `.dart_tool/comments-sheet-23-final-tests.log` và `.dart_tool/comments-sheet-23-final-analyze.log`. Có 13 widget test bổ sung trong các lượt Like/bình luận và popup: bấm lặp/hoàn tác/timeout/offline, bản tạm/ID thật/nháp, cuộn bài phía sau, không push route, gửi đúng thread, màn nhỏ/chữ lớn/bàn phím và đóng/Back. Kết quả 222 test trong `optimistic-23-final-*` là lượt trước popup. APK debug x86_64 đã build và cài đè thành công lên emulator-5554 (Medium_Phone_API_37.0) ngày 23/11; đã mở bảng tin và cửa sổ bình luận, tải được bình luận thật. Cài bằng -r giữ dữ liệu; đã cold boot không wipe để xử lý phiên cài Android bị kẹt. Không gửi bình luận/Like hay thao tác ghi nghiệp vụ trong lượt cài. Chưa build lại release ARM64 hoặc nghiệm thu trọn luồng trên điện thoại/server thật.

**Hoàn thiện 22/11:** đã bổ sung xóa/thu hồi tin qua `DELETE /messages/{id}` đúng scope ME/EVERYONE và quyền người gửi; UI nhấn giữ có xác nhận, chỉ cập nhật sau server. Có marker bảo mật chống replay sau lỗi mạng, loại GET cũ, xử lý revoked và đồng bộ preview hội thoại/cache theo user. `ChatChanges` là sự kiện nội bộ feature chat, không phải tính năng người dùng. Đã gỡ công cụ đối chiếu ID ngoài PDF. **213 test đạt, analyze sạch**; xem mục hoàn thiện 22/11 trong [báo cáo](docs/thay-doi-pdf-2026-11-19.md). Các ghi chép bên dưới về thiếu xóa/thu hồi là lịch sử đã được sửa. Push/QUESTION và nghiệm thu server/hai điện thoại thật vẫn có giới hạn được ghi rõ; không tuyên bố hoàn thành 100% từ test.

**APK bản cuối 22/11:** debug x86_64 và release ARM64 (22,2 MB) build thành công sau các sửa phân trang/preview, log `complete-22-*`. Chưa cài/chạy bản cuối trên máy thật. Khi đánh giá, phân biệt rõ chức năng đã có code, giới hạn hợp đồng/cấu hình và kịch bản chưa nghiệm thu; không biến vấn đề đối soát gửi chat thành tính năng người dùng ngoài PDF.

**Điều chỉnh 22/11:** đã gỡ màn chọn/liên kết ID tin và thao tác bỏ bản cục bộ ngoài PDF. Trạng thái chưa xác nhận chỉ tải lại lịch sử, không tự gửi lại. Analyze sạch, 202 test đạt (`scope-22-*`); đã bỏ kiểm thử riêng của chức năng thừa. Chưa build lại APK sau thay đổi này.

**Rà soát bổ sung 20/11:** cấu trúc Swagger tải lại không đổi so với 19/11. Phát hiện chat **chưa có thao tác xóa/thu hồi** qua `DELETE /messages/{id}` scope ME/EVERYONE (PDF mới trang 185); chỉ nhận MESSAGE_REVOKED chưa đủ thay thế thao tác này. Không tuyên bố mọi chức năng chat đã đủ. Xem mục rà soát 20/11 trong [báo cáo](docs/thay-doi-pdf-2026-11-19.md); lượt này chưa sửa code.

**Kiểm chứng bản cập nhật 19/11:** 203 test đạt, analyze sạch; APK debug x86_64 và release ARM64 (22,2 MB) build thành công. Log `update-19-*` trong `.dart_tool`. Chưa nghiệm thu bản này trên điện thoại thật/server nghiệp vụ; push vẫn chờ cấu hình và chat vẫn cần làm rõ tương quan xác nhận tự động với backend.

**Cập nhật theo PDF/Swagger ngày 19/11/2026:** xem [bản đối chiếu và phần cập nhật code](docs/thay-doi-pdf-2026-11-19.md). PDF hiện hành được lưu tại `docs/Social Network for Student-Generated Question Bank-2026-11-19.pdf` (207 trang); bản 208 trang là lịch sử. Login mới dùng `/auth/native/login`; refresh/logout dùng `/auth/native/*` cho phiên native. `SessionTokens.nativeAuth` được lưu bảo mật cùng token; record cũ thiếu cờ giữ kênh legacy, không gửi RT cũ sang native, không xóa phiên chỉ vì cập nhật app/offline. Phiên cũ chỉ còn chạy khi server hỗ trợ tương thích, đăng nhập lại sẽ nhận phiên native. Token ONBOARDING không mở shell/không được lưu như phiên đầy đủ; hướng dẫn liên hệ giảng viên với tài khoản chưa ACTIVE, không gọi API xác minh admin. Soạn bài cá nhân chỉ chọn/chụp tối đa 4 ảnh tĩnh; bỏ chọn/quay video, giữ xem video giảng viên và giữ draft cũ có video nhưng yêu cầu gỡ trước khi đăng. SESSION notification kiểm tra đề xuất của mình, chỉ thử luyện tập khi server trả 403/404, giữ cache đúng tài khoản khi lỗi mạng. Chat cho đối chiếu thủ công bản chưa xác nhận với ID tin máy chủ do người dùng chọn; không tự ghép theo text/thời gian hoặc tự replay. Kết quả kiểm chứng cuối ghi trong báo cáo; không dùng kết quả 194 test cũ để kết luận bản 19/11 đã nghiệm thu server thật.

**Đối chiếu tiếp ngày 18/11/2026:** xem [ma trận PDF–Swagger–code và kết luận đủ/thiếu](docs/doi-chieu-pdf-swagger-2026-11-18.md). Đã sửa đọc thông báo dùng đúng `read`, `read_at`, `unread_count` server thay vì tự trừ; GET cũ không ghi đè kết quả đọc. Xóa mã tạo nhóm/GIF không sử dụng, kiểm tra ảnh chat động/hỏng và ảnh hồ sơ động; bổ sung tìm bài từ trang chủ và mở ảnh hồ sơ bằng viewer chung; dùng `next_cursor` và `last_message.message_id` đúng schema hội thoại. Bỏ nhãn chat “Trực tuyến” cố định và trường gửi STOMP ngoài schema. Cache thông báo và ngân hàng câu hỏi chuyển sang `DraftStore` bảo mật, có chuyển cache cũ khi đọc và giữ bản offline cũ nếu chuyển lỗi. Mật khẩu mới chỉ chữ/số theo PDF. **194 kiểm thử đạt, analyze sạch.** Đã kiểm tra khởi động một bản debug trên emulator trong đợt; chưa nghiệm thu lại toàn bộ API trên server, hai điện thoại thật, push hay thu/phát âm thanh native. Người dùng xác nhận **chưa có cấu hình Firebase từ thầy**; phần push đang chờ cấu hình, không coi đã hoàn thành nghiệm thu. Xem báo cáo để biết bản APK đã build và giới hạn điều hướng câu hỏi/xác nhận socket. Không suy ra server thật đã được nghiệm thu từ các test hợp đồng.

**Hoàn thiện bổ sung 17/11/2026 trên nền `0b30ad9`:** đã sửa các lỗi trong đợt rà soát: TLS/vòng đời/STOMP chat, gửi/chưa xác nhận/retry/cache riêng tư, thông báo đã đọc, race cài đặt, chặn/bỏ chặn đồng bộ bảng tin và emote giữ nguyên URL. Đối soát bài/bình luận sau timeout dùng cùng nội dung đã chuyển emote với request, tránh kết luận nhầm rồi gửi trùng. Đã bổ sung frontend nhận push bằng FID và thu âm/nghe thử. Analyze sạch, **176 test đạt**; build debug x86_64 và release ARM64 thành công. Đã cài debug lên emulator, kiểm tra đăng nhập rỗng và mở lại offline khi chưa có phiên. Xem [bàn giao bản sửa, cấu hình và giới hạn](docs/hoan-thien-luong-2026-11-17.md). Báo cáo rà soát trước đó là lịch sử phát hiện, không phải trạng thái lỗi chưa sửa hiện tại. Chưa nghiệm thu điện thoại thật, API nghiệp vụ, push server thật hoặc thu/phát âm thanh thực tế trong đợt này.

- **Mục 1 (`features/auth`, `features/settings`):** Đã có màn đăng nhập qua API, lưu phiên, callback refresh, đăng xuất cục bộ/server và đổi mật khẩu. `main.dart` gắn `AuthApplication` vào khung qua builders/routes công khai. Đã sửa mã thành công mặc định trong `AppConfig` thành **`1000`** theo response server thật. `android/gradle.properties` đặt `kotlin.incremental=false` để tránh lỗi cache khi project ở D: và Pub cache ở C:.
- **Mục 4 (`features/profile`, `features/relationships` — cập nhật 04/11):** Đã nối tab Cá nhân (`ProfileScreen`) và tab Bạn bè (`RelationshipsScreen`, `FriendFinderScreen` tìm người qua `GET search?type=USER`), có danh sách chặn, `SocialChanges`/`SocialLease` vô hiệu dữ liệu khi quan hệ thay đổi, route `ProfileRoutes.user` (`/profile/user`). Xem [bàn giao hồ sơ và quan hệ](docs/module-ho-so-quan-he.md).
- **Mục 3 (`features/question_bank` — cập nhật 10/11):** Đã nối `AppTab.questionBank` (`QuestionBankTab`) và `QuestionBankRoutes.routes` (`/question-bank/compose`, `/question-bank/submission`, `/question-bank/practice`, `/question-bank/ratings`). Xem [bàn giao mục 3](docs/muc-3-question-bank.md).
- **Mục 5 (`features/notifications`, `features/chat`, `features/settings` trên nhánh `feat5`):** Đã nối `AppTab.notifications` (`NotificationsTab`), `/conversations` (`ConversationsScreen`), `/chat` (`ChatDetailScreen`), `SettingsRoutes.pushSettings` (`/settings/push`), cùng GitHub Actions workflow build APK debug. Đã đối chiếu OpenAPI trực tiếp ngày 12/11/2026.
- **Mục 2 (`features/feed`, `features/posts`):** Bảng tin, bài của tôi, soạn/sửa/xóa bài, Like, bình luận, báo cáo và ảnh/video. Gắn `FeedScreen` qua `AuthApplication.tabBuilders` tại `main.dart`; `PostRoutes.routes` đăng ký `/posts/detail`, nhận `{'postId': id}` từ thông báo, hoặc ID nguyên/chuỗi. Route kiểm tra ID và dùng cơ chế bảo vệ phiên chung. Xem [bàn giao mục 2](docs/muc-2-feed-posts.md).

### Lưu ý tích hợp phần 2

- Giữ builder/route của các thành viên khác; không khôi phục tab Cá nhân tạm của nhánh feat2 cũ. Không sửa implementation `app/core` để ghép feed.
- Giữ `shared_preferences_android` 2.5.4 hoặc bản tương thích có sửa lỗi R8/JNI. Bản 2.5.1 đã làm cache lỗi trên APK release dù unit test đạt. Giữ dependency video_player cho trình phát video.
- Feed cache theo tài khoản, tối đa 40 mục/512 KiB trên đĩa và 200 mục RAM. Chỉ lưu bài PUBLIC cùng trường hiển thị sự kiện. Bản nháp media dùng tệp bền vững và dấu chủ sở hữu picker để tránh khôi phục nhầm tài khoản.
- Backend có thể giữ sự kiện CREATED_POST sau khi xóa bài. Phải kiểm tra chi tiết, lọc 403/404 và vẫn cho tải trang kế tiếp khi trang hiện tại bị lọc hết. Không replay thao tác ghi sau timeout; cần đối soát trước khi thử lại.
- Đã kiểm tra backend thật và Android ảo ngày 05–07/11: đăng ảnh/video, phát video, Like, bình luận, sửa/xóa; tắt toàn bộ mạng rồi force-stop/mở lại vẫn thấy bài và ảnh cache. Dữ liệu thử đã dọn. Kết quả kiểm thử tích hợp ngày 14/11 ghi riêng trong bàn giao; không coi các lần kiểm tra trước là nghiệm thu bản merge hoặc điện thoại vật lý.

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
| `lib/features/question_bank/question_bank_cache.dart` | `QuestionBankCache`: adapter interface `JsonCache`, dùng `DraftStore` cho nguồn đề xuất/trạng thái trả lời riêng tư; chuyển cache preferences cũ khi đọc |
| `lib/features/search/` | `PostSearchRepository`, `PostSearchController`, `PostSearchScreen`: tìm bài từ trang chủ, phân trang offset, bỏ response truy vấn/phiên cũ |
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
  - Nội dung thông báo/chat và cache ngân hàng câu hỏi riêng tư dùng `DraftStore`; chỉ loại bản preferences cũ sau khi chuyển thành công. Nếu chuyển lỗi, giữ bản offline cũ đúng tài khoản và thử chuyển lại khi đọc sau; không ghi dữ liệu mới trở lại plaintext.

---

## 6. Hợp đồng nghiệp vụ & API cần nhớ

- PDF quy định nghiệp vụ; Swagger quy định hợp đồng API hiện tại. Có endpoint không đồng nghĩa phải đưa tính năng vào app. PDF trang 25 cấm lập nhóm chat, trang 27 cấm tham gia/tạo nhóm và không làm việc với ảnh động: giữ chat 1–1, không có lối gửi GIF. Những API có thể hỗ trợ thêm (nhóm, reaction khác Like, ảnh/sửa bình luận, xóa tài khoản) không tự mở rộng giao diện. Nếu hai nguồn mâu thuẫn, ghi khác biệt cụ thể và phần cần xác nhận; không tự bịa hợp đồng.
- **Bắt buộc đọc kỹ Swagger từng endpoint trước khi code hoặc sửa tích hợp:** method/path, token/quyền, nền tảng, content type, tham số, enum/nullability, phân trang và response thành công/thất bại. Không chỉ sao chép JSON ví dụ hoặc suy đoán theo tên API. [Swagger](https://snsqb.duckdns.org/api/v1/swagger-ui/index.html), [OpenAPI JSON](https://snsqb.duckdns.org/api/v1/docs/openapi.json).
- Phân biệt ví dụ với schema và response thật. Nếu Swagger khác server, ghi nhận khác biệt không chứa thông tin đăng nhập/token, cập nhật mapping/test phù hợp; không coi mọi HTTP 200 là thành công hoặc báo tích hợp thật chỉ từ test giả. Phần chưa kiểm chứng phải ghi rõ.
- **Base URL:** `https://snsqb.duckdns.org/api/v1/`
- **Mã thành công chuẩn:** **`1000`**. Swagger mới đã ghi đúng `1000`; các tài liệu/ví dụ cũ dùng `0000` không thay thế hợp đồng hiện tại.
- **Auth Android:** login mới `/auth/native/login`, refresh `/auth/native/refresh`, logout `/auth/native/logout`. Không trộn token NATIVE với kênh WEB cookie hoặc LEGACY_JSON. Phiên cũ chỉ dùng endpoint cũ đúng kênh cho đến khi đăng nhập lại; khi backend bỏ tương thích và từ chối refresh, yêu cầu đăng nhập lại. Không tự thử nhiều endpoint cho cùng thao tác ghi.
- Mật khẩu mới do người dùng đặt: chữ cái A–Z/a–z và chữ số, không khoảng trắng/ký tự đặc biệt theo PDF trang 23; kiểm tra trước mạng. Swagger không khai báo pattern, ví dụ có `@` không thay thế nghiệp vụ. Mật khẩu được thầy cấp/mật khẩu hiện tại vẫn gửi nguyên trạng, không trim hoặc sửa khi đăng nhập.
- **Header bắt buộc:** `Authorization: Bearer <access_token>` (trừ login/refresh).
- **Kiểu dữ liệu theo OpenAPI thực tế (cập nhật 12/11/2026):**
  - `CursorPaginationDto.after` và `before` là **số nguyên (`int64`)**, luôn đọc qua `?.toString()`.
  - `CreateDirectConversationDto` gửi `target_user_id` dạng **số nguyên (`int64`)**; response `ConversationDetailDto` trả `conversation_id`, `name`, `avatar_url`, `members`.
  - `NotificationTargetDto` dùng `target_id` (int64) và `type` enum `BADGE | SESSION | POST | QUESTION | USER | CONVERSATION`.
  - `PushSettingsResponseDto` & `UpdatePushSettingsRequestDto` dùng **boolean** (`true`/`false`) cho `push_enabled`, `sound_enabled`, `vibration_enabled`, `categories[K].enabled`; các key category là `SOCIAL`, `ACADEMIC`, `GAMIFICATION`, `SYSTEM`.
  - `SyncFidRequest` (`POST /devices/fid`) gửi `{"fid": "..."}`.
  - `POST notifications/{id}/read`: response `ReadNotificationResponseDto` dùng `read`, `read_at`, `unread_count`; PDF trang 196 dùng tên cũ `is_read`. Lấy số đếm/thời gian server, không tự trừ 1. `read-all` trả `data: null`. PDF không bắt buộc optimistic read; cập nhật sau xác nhận là lựa chọn xử lý lỗi của app.
  - Hội thoại có `next_cursor` đầy đủ; gửi nó qua query `cursor` cho trang sau khi có, dùng `after` làm phương án tương thích. `last_message` dùng `message_id`, không phải `id`.
- **Giới hạn bài viết & bình luận:** Tối đa 500 từ. Theo PDF mới trang 23/27/28, bài cá nhân chỉ chọn/chụp tối đa 4 ảnh tĩnh, 4 MB/ảnh; không quay/chọn video mới. Giữ trình xem video bài giảng do giảng viên đăng. Không suy việc PDF bỏ giới hạn video cũ thành cho phép upload video vô hạn. Draft cũ không bị tự xóa; muốn đăng phải gỡ video mới đang đính kèm. Bài video đã có vẫn có thể hiển thị, và sửa nội dung không tự xóa media cũ.
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
- `NotificationsTab` gắn vào `AppTab.notifications` của `AppShell`, hỗ trợ bộ lọc (Tất cả / Chưa đọc / Ngân hàng đề), Pull-to-refresh, tải thêm (`after`, `has_next`), đọc từng mục/tất cả qua POST tương ứng. Chỉ cập nhật đã đọc sau xác nhận; dùng số đếm/thời gian server, không replay POST khi timeout. Không bỏ thao tác đọc chỉ vì đang refresh; response GET cũ phải bị loại.
- `NotificationDeepLinkHandler` điều hướng tới `ChatDetailScreen`, `ProfileRoutes.user`, `QuestionBankRoutes.submission`, `/posts/detail` và bắt lỗi an toàn (không crash khi 404/403 hoặc route chưa merge).
- Offline cache thông báo qua `DraftStore` bảo mật theo `userId`, tối đa 30 mục/512 KiB; chuyển record `JsonCache` cũ rồi loại bản preferences. Không lưu nội dung thông báo riêng tư vào preferences.

### B. Trò chuyện 1–1 Realtime & Offline (`lib/features/chat`)
- Chỉ làm **chat 1–1 (Direct chat)**, không làm chat nhóm; không hỗ trợ tag `@username`.
- `ConversationsScreen` (`/conversations`): `GET /conversations`, tạo chat 1–1 `POST /conversations/direct`, tìm kiếm nhanh, cache offline.
- `ChatDetailScreen` (`/chat`): `GET /conversations/{id}/messages`, Reverse scroll, bong bóng chat, trạng thái Đang gửi / Đã gửi / Lỗi thử lại, xem ảnh toàn màn hình phóng to (`InteractiveViewer`), cảnh báo khi bị chặn, upload ảnh qua `deps.mediaUpload` (`MediaPurpose.chat`, $\le 4\text{MB}$).
- STOMP WebSocket WSS (`wss://snsqb.duckdns.org/api/v1/ws`): subscribe `/user/queue/messages` và phân loại sự kiện; send `/app/chat.send`, `/app/chat.read`, `/app/chat.typing` (trường `typing`, ID số). Không dựa vào các topic typing/read ngoài OpenAPI. Reconnect có kiểm soát, không tự replay thao tác gửi.
- `ChatEmoteConverter`: chuyển đổi ký tự emote (bao gồm `<(")` → 🐧, `(^^^)` → 🦈, `:))` → 😆, `:)` → 😊, `<3` → ❤️, v.v.).
- Lưu text/outbox và cache tin riêng tư qua secure storage (`DraftStore`), có giới hạn tài nguyên và namespace theo user. Không ghi tin riêng tư vào preferences. Mã `client_msg_id` dùng cục bộ, không gửi lên STOMP vì Swagger chưa khai báo; chưa xác nhận backend có echo/chống trùng. Trạng thái `unconfirmed` chỉ cho tải lại/đối chiếu, không gửi lại mù quáng; cần nghiệm thu xác nhận tin bằng hai tài khoản với server thật.

### C. Cài đặt Thông báo & Thiết bị (`lib/features/settings`)
- `PushSettingsScreen` (`SettingsRoutes.pushSettings = '/settings/push'`): `GET /settings/push`, `PUT /settings/push`, công tắc chuyên mục (`SOCIAL`, `ACADEMIC`, `SYSTEM`), rung/chuông, tùy chọn kiểu âm thanh mặc định hoặc giọng nói thu âm (Slide 26 & 29), đăng ký/hủy thiết bị (`POST /devices/fid`, `POST /devices/fid/unregister`).
- Cấu hình Firebase client qua `PushConfig` (template trong docs); không tạo backend mới. SDK Messaging 17.1 dùng `register`/`onRegistered` để lấy FID theo tài liệu hiện tại. Chưa có cấu hình đúng project của server thì không khởi tạo SDK và không tuyên bố push hoạt động. `sound_type` là lựa chọn cục bộ, không nằm trong REST schema. Android compile SDK 37, có quyền micro/thông báo và FileProvider chỉ chia sẻ tệp thu âm của app. Xem bàn giao để phân biệt data-only với notification payload ở nền.

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
