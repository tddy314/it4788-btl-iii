# Mục 3 — Ngân hàng câu hỏi (`features/question_bank`)

Cập nhật 10/11/2026. Đối chiếu OpenAPI cùng ngày. Gắn vào khung qua `AuthApplication`: `AppTab.questionBank` → `QuestionBankTab`, route con qua `QuestionBankRoutes.routes`. Không sửa `core`, `app`, theme.

## Chức năng

| Phần | Màn hình | API |
| --- | --- | --- |
| Đề xuất câu hỏi | `ProposalComposerScreen` | `GET sessions/my-enrolled-course-classes`, `POST medias/upload?purpose=QUESTION`, `POST sessions/propose` |
| Theo dõi đề xuất | `MySubmissionsView`, `SubmissionDetailScreen` | `GET sessions/my-submissions` (lọc `status`), `GET/PUT/DELETE sessions/my-submissions/{id}` |
| Luyện tập | `PracticeCatalogView`, `PracticeScreen` | `GET subjects`, `GET sessions/practice-catalog` (`q`, `subject_id`), `GET sessions/{id}/questions`, `POST questions/{id}/answer` |
| Đánh giá | Bottom sheet trong `PracticeScreen`, `QuestionRatingsScreen` | `POST questions/{id}/rate`, `GET questions/{id}/ratings`, `PUT questions/{id}/report` |

Không gọi `lecturer/*`, `admin/*`, AI hay minigame. Không làm bình luận/cảm xúc trên phiên (thuộc phần dùng chung của mục 2).

## Hợp đồng cần nhớ (theo Swagger hiện tại)

- Đề xuất theo **lớp học phần** (`course_class_id`), chỉ lớp `can_propose=true`. Tối thiểu **3 câu**. Mỗi câu bắt buộc `content`, `options`, `llm_generated`, `confidence` 0–4.
- Tạo dùng `llm_generated` + `media_urls`, sửa dùng `source: LLM|HOMO_SAPIENS` + `question_id` (null nếu câu mới). Đọc chi tiết dùng `image_urls`, `confidence_score`.
- `options` là object `{key, text, is_correct}`. App sinh khóa A, B, C… theo thứ tự, cho phép nhiều đáp án đúng, bắt buộc ít nhất 1.
- Trạng thái phiên PENDING/REVIEWING/RESOLVED tách biệt với kết quả từng câu (APPROVED/REJECTED + `rejection_code`). UI ghi rõ "Đã xử lý" không có nghĩa mọi câu được chọn.
- Sửa/xóa chỉ khi PENDING **và** dữ liệu vừa tải từ server (không cho thao tác trên dữ liệu cache).
- Trả lời: `selected_options` + `question_updated_at` lấy từ server. 409 = đã trả lời, 412 = câu hỏi đã đổi → tải lại. Đáp án/đúng-sai chỉ lấy từ server; `is_correct` bị ẩn giữ là null, không hiểu là "sai".
- Đánh giá là số nguyên 0–4 (0 hợp lệ). Nhận xét và báo lỗi tối đa 500 **ký tự**. Rate/report là upsert nên gửi lại không tạo bản trùng.
- Màn luyện tập không hiển thị nguồn AI/tự làm. Chỉ màn chi tiết đề xuất của chính tác giả mới hiện nguồn và mức tự tin.

## Mất mạng, timeout, bản nháp

- Cache theo tài khoản (preferences): trang đầu "Đề xuất của tôi" theo từng bộ lọc, trang đầu kho luyện tập khi không lọc (tối đa 20 mục), danh sách lớp/môn, chi tiết đề xuất và bộ câu hỏi đã mở. Lỗi mạng giữ dữ liệu cũ kèm thông báo thời điểm lưu. 401/403/404 xóa cache tương ứng.
- Phân trang `PagedListController`: tăng generation khi đổi bộ lọc/refresh để bỏ phản hồi cũ, loại trùng theo ID, dừng khi cursor lặp. Lỗi load-more không tự gọi lại; người dùng bấm "Thử lại". Tìm kiếm debounce 400 ms.
- Bản nháp (`DraftStore`, secure storage) theo user: `qb-proposal-new`, `qb-proposal-edit-{id}`. Lưu sau 600 ms khi gõ, trước khi mở camera/thư viện và khi rời màn. Chỉ xóa sau khi server xác nhận.
- Ảnh được kiểm tra chữ ký JPEG/PNG/WebP (không tin đuôi file), ≤ 4 MB, từ chối ảnh động, rồi sao chép vào `ApplicationSupport/question_bank_drafts/{user}` để sống qua lần mở lại app. Upload lần lượt; ảnh đã có URL không upload lại.
- Gửi: validate → lưu nháp → upload ảnh còn thiếu → **ghi cờ `pending` vào nháp** → POST/PUT. Lỗi rõ ràng (offline trước khi gửi, 400/403) thì gỡ cờ. Timeout/5xx/phản hồi hỏng thì giữ cờ. Lần gửi sau sẽ kiểm tra trước:
  - Tạo mới: tìm `my-submissions?q=<tiêu đề>`. Nếu có phiên cùng tiêu đề, đủ số câu và tạo trong vòng 1 giờ quanh lần gửi thì mở phiên đó, không POST lại.
  - Sửa: tải chi tiết, gán `question_id` cho câu mới đã được thêm (so nội dung) rồi mới PUT, tránh nhân đôi câu.
  - Kiểm tra lỗi mạng → không gửi.
- Xóa bị timeout: không gửi lại DELETE, tải chi tiết để xác minh (404 = đã xóa).
- Swagger: `propose` trả 404 khi ảnh tạm hết hạn → app xóa URL của ảnh còn tệp trên máy để upload lại ở lần gửi sau.

## Kiểm thử

`flutter analyze` sạch. `flutter test`: 66 test đạt, trong đó 35 test mới ở `test/features/question_bank/`:

- Unit (29): parse lỏng/enum lạ/thiếu ID, `is_correct` ẩn, validation (0 hợp lệ, 3 câu, trùng đáp án, URL, 500 ký tự, chữ ký ảnh), payload tạo/sửa, phân trang (cache offline, 403, phản hồi cũ, dedupe), repository (query, mã lỗi 2002, HTTP 200 + code lỗi), controller (validate trước mạng, offline, upload từng phần, timeout → không POST lại, kiểm tra offline không gửi, sửa bị khóa, PUT timeout không nhân đôi câu, nháp tách tài khoản, từ chối quyền camera).
- Widget (6, qua `AuthApplication`): danh sách + lọc + chi tiết kết quả một phần; mở app offline có cache; form lỗi không gọi mạng trên màn 320×640, font 1.5×; gửi đề xuất đầy đủ; luyện tập (chưa chọn đáp án, kết quả server, 409, đánh giá 0); xóa timeout được xác minh bằng GET.

Đã build `flutter build apk --debug` với plugin `image_picker 1.2.4`, `path_provider 2.1.6` (cùng phiên bản nhánh feat2).

## Chưa xác nhận

- **Chưa chạy với server thật** (không có tài khoản thử; GET không token đều trả 401 trước khi định tuyến). Cần đăng nhập thật để đối chiếu: response `propose` (HTTP 201 + code 1000?), `PUT/DELETE` trả `data` là `{}` hay thiếu (thiếu `data` thì core coi là dữ liệu không hợp lệ → app đi nhánh "chưa xác nhận" và tự kiểm tra lại), mã lỗi thực tế của 409/412, định dạng `correct_answer` khi nhiều đáp án.
- Chưa thử trên điện thoại thật: camera, thu hồi quyền, Android hủy activity lúc đang chụp (chưa xử lý `retrieveLostData`), ngắt mạng giữa upload.
- Chưa có thêm ảnh cho từng đáp án (`media_url` của option chỉ được giữ nguyên khi sửa).
