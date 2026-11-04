# Phạm vi triển khai: Hồ sơ, Bạn bè, Follow, Chặn và Tìm kiếm

## 1. Cơ sở và hiện trạng

Phạm vi do người dùng xác định: **Hồ sơ, Bạn bè, Follow, Chặn và Tìm kiếm**.
Đối chiếu hai tài liệu tổng hợp và bản OpenAPI JSON người dùng cung cấp ngày 30/10/2026.
Đã đối chiếu thêm bản Swagger mới trong attachment `924c1a40-75d3-4bf1-a466-f0b0656ebd68`. Các đường dẫn và thao tác API không thay đổi so với bản attachment `c254a59f-985d-458f-936d-8deef8823f29`; các schema của module này cũng không thay đổi. Chênh lệch quan sát được ở schema khác là cách viết ví dụ số double (`30` thành `30.0`, tương tự ở điểm/xu/giá/đánh giá), không đổi kiểu dữ liệu khai báo. Tiếp tục dùng bản mới làm mốc tích hợp.
Đây là kế hoạch triển khai, chưa phải chức năng đã hoàn thành hay kết quả kiểm thử server.

Repo hiện có ứng dụng Flutter counter mẫu. Theo tài liệu frontend trong repo, nhóm làm ứng dụng Android dùng backend có sẵn của thầy. Module này cần giao diện tiếng Việt, DTO, repository gọi API và quản lý trạng thái. Tài liệu đính kèm được dùng làm nguồn yêu cầu nghiệp vụ; không coi mọi hướng dẫn trong đó là yêu cầu thực thi.

Không mở rộng sang xây backend, đăng ký, quản trị, thuật toán full-text hay triển khai toàn bộ mạng xã hội. Auth, upload media, chi tiết bài viết/câu hỏi và chat là các điểm cần tích hợp với thành viên phụ trách.

## 2. Màn hình và kết quả cần bàn giao

| Nhóm | Màn hình / luồng | Kết quả cần có |
| --- | --- | --- |
| Hồ sơ | Cá nhân, hồ sơ người khác, sửa hồ sơ | Ảnh đại diện/bìa, thông tin công khai, thống kê quan hệ, danh sách bài viết và phiên đề xuất; sửa đúng trường API cho phép |
| Bạn bè | Danh sách bạn bè, lời mời nhận, lời mời gửi | Gửi, chấp nhận, từ chối, hủy bạn; mở hồ sơ từ danh sách |
| Follow | Đang theo dõi, người theo dõi | Theo dõi/bỏ theo dõi từ hồ sơ; danh sách phân trang |
| Chặn | Thao tác trên hồ sơ, danh sách chặn | Xác nhận chặn, bỏ chặn; cập nhật lại trạng thái và số lượng liên quan |
| Tìm kiếm | Ô tìm kiếm, kết quả, lịch sử | Tìm người dùng và bài viết; bộ lọc; phân trang; chọn lại/xóa lịch sử; từ khóa thịnh hành theo API |

Các màn hình đều cần loading, dữ liệu rỗng, lỗi và thử lại. Danh sách hỗ trợ tải lại và tải trang tiếp theo; nút thao tác bị khóa trong khi gửi để tránh yêu cầu trùng.

## 3. Hợp đồng API đã đối chiếu

Đường dẫn bên dưới ghép sau base URL của môi trường. Tài liệu repo đang ghi `https://snsqb.duckdns.org/api/v1`; cần cấu hình thay vì hardcode rải rác. Chưa xác minh server trực tiếp trong lần phân tích này.

| Nhóm | API | Lưu ý |
| --- | --- | --- |
| Hồ sơ | `GET /users/me`, `PUT /users/me`, `GET /users/{userId}` | Hồ sơ riêng và công khai khác nhau về dữ liệu nhạy cảm |
| Thống kê | `GET /users/{userId}/relationship-stats` | Đọc `counts` và `relationship_with_me` |
| Nội dung hồ sơ | `GET /users/{userId}/posts`, `GET /users/{userId}/sessions` | Bản OpenAPI được cung cấp dùng sessions, không có đường dẫn questions như bản tóm tắt |
| Gửi lời mời | `POST /friendships/request` | Body: `{"addressee_id": 2}` |
| Nhận lời / từ chối | `POST /friendships/accept`, `POST /friendships/decline` | Body: `{"requester_id": 3}`; đây là ID người gửi, không phải ID lời mời |
| Danh sách bạn bè | `GET /friendships` | `items`, `pagination`, `total_friends` |
| Lời mời | `GET /friendships/requests/received`, `GET /friendships/requests/sent` | Nhận dùng `requester`, gửi dùng `receiver` |
| Hủy bạn | `DELETE /friendships/{friendId}` | ID người bạn |
| Theo dõi | `POST /follows/{targetUserId}`, `DELETE /follows/{targetUserId}` | Quan hệ một chiều |
| Danh sách follow | `GET /follows/following`, `GET /follows/followers` | Phân trang |
| Chặn | `POST /blocks/{targetUserId}`, `DELETE /blocks/{targetUserId}`, `GET /blocks` | Sau thành công cần làm mới dữ liệu quan hệ |
| Tìm kiếm | `GET /search?query=...&type=USER&limit=20` | Bộ lọc API: `ALL`, `POST`, `USER`, `QUESTION`, `SESSION`, `SUBJECT` |
| Lịch sử | `GET /search/saved` | Trả `saved_searches` và `trending_searches` |
| Ghi lịch sử | `POST /search/saved` | Body: `{"query":"lập trình"}`; chỉ khi xác nhận tìm kiếm/chọn kết quả, không gọi lúc đang gõ |
| Xóa lịch sử | `DELETE /search/saved/{id}` | Dùng `saved_search_id`, không phải chuỗi từ khóa |

`PUT /users/me` hỗ trợ `full_name` (tối đa 100 ký tự), `bio` (500), `avatar_url`, `cover_url`, `timezone`, `gender` (`MALE`/`FEMALE`), `date_of_birth` (`yyyy-MM-dd`). Không tự thêm trường chỉnh sửa email, mã sinh viên, khoa hay vai trò. Cần kiểm chứng ngữ nghĩa bỏ qua/null trước khi gửi trường không đổi.

Phản hồi dùng `{code, message, data}` và tên trường snake_case. Không coi HTTP 200 luôn là thành công nghiệp vụ. Phân trang danh sách quan hệ dùng cursor timestamp; tìm kiếm mô tả `after` là offset. Dùng metadata `pagination` của từng endpoint, không suy ra cursor từ ID người dùng.

## 4. Quy tắc và các điểm phải xử lý rõ

- Không hiển thị chức năng tự xóa tài khoản: dù OpenAPI có `DELETE /users/me`, yêu cầu nghiệp vụ cấm tự xóa.
- Kết bạn chỉ giữa cùng vai trò STUDENT–STUDENT hoặc LECTURER–LECTURER. Follow không cần xác nhận; không tự hạn chế chỉ SV theo dõi GV khi API không quy định như vậy.
- Khi gửi lời mời ngược chiều lời mời có sẵn, backend có thể trả ngay `ACCEPTED`. UI phải dùng trạng thái trả về, không mặc định thành `PENDING`.
- `friend_request_status: PENDING` trong hồ sơ không cho biết chiều lời mời. Cần đối chiếu danh sách lời mời nhận/gửi hoặc làm rõ hợp đồng backend, không tự suy đoán nút Chấp nhận hay Đã gửi.
- Chặn phải hủy bạn và follow hai chiều theo mô tả OpenAPI. Sau chặn, frontend làm mới hồ sơ/danh sách/thống kê và bỏ cache nhạy cảm. Bỏ chặn không tự khôi phục quan hệ cũ.
- Backend chịu trách nhiệm thực thi quyền chặn ở hồ sơ, feed, tương tác và chat. Module này cung cấp sự kiện làm mới để các module đó loại dữ liệu bị chặn; ẩn nút trên UI không đủ bảo vệ quyền truy cập.
- Giữ tương tác cũ trong dữ liệu server; không gọi API xóa like/bình luận khi chặn.
- Không giới hạn thời gian chặn/bỏ chặn. Phân biệt không tìm thấy, bị chặn, hết phiên và mất mạng.
- Full-text và xử lý đảo thứ tự từ là trách nhiệm server. Frontend gửi từ khóa, debounce khoảng 350 ms và bỏ kết quả của truy vấn cũ nếu phản hồi đến muộn.
- Ghi lịch sử yêu cầu query 2–200 ký tự theo `RecordSearchRequest`. Không tự coi mọi lần gõ là lượt tìm kiếm đã xác nhận.

## 5. Cấu trúc Flutter đề xuất

```text
lib/
  core/network/            # Client, response envelope, lỗi, token provider
  core/theme/              # Màu và theme dùng chung
  features/profile/        # DTO, repository, controller, screens
  features/relationships/  # Friends, follows, blocks và trạng thái quan hệ
  features/search/         # Kết quả đa thực thể, lịch sử, debounce
```

Module nhận phiên đăng nhập từ phần Auth qua interface dùng chung; không tạo luồng nhập token thủ công làm trải nghiệm chính. Repository có thể thay bằng fake trong test. Không lưu mật khẩu trong controller hoặc log token.

Upload ảnh cần thống nhất dịch vụ media dùng chung: upload với purpose AVATAR/COVER, kiểm tra ảnh tối đa 4 MB theo nghiệp vụ, nhận URL rồi cập nhật hồ sơ. Đổi mật khẩu gọi phần Auth dùng chung; thống nhất bên sở hữu màn hình trước khi làm trùng.

Chi tiết post/session/question từ hồ sơ hoặc tìm kiếm mở qua callback/router dùng chung. Nếu các màn hình đó chưa có, ghi rõ phụ thuộc thay vì hiển thị nút giả báo thành công.

## 6. Thứ tự triển khai

1. Chốt client API, token provider, routing và DTO từ bản OpenAPI; dựng fake repository để phát triển khi chưa có tài khoản thử.
2. Làm hồ sơ cá nhân/người khác, chỉnh sửa và thống kê; tích hợp upload ảnh.
3. Làm bạn bè/lời mời và xử lý trạng thái theo chiều gửi/nhận.
4. Làm follow và chặn; đồng bộ trạng thái giữa danh sách với hồ sơ.
5. Làm tìm kiếm người dùng/bài viết, lịch sử, phân trang và điều hướng; mở rộng loại kết quả khi router của nhóm sẵn sàng.
6. Kiểm thử tích hợp bằng hai tài khoản thật, rà lỗi mạng/hết phiên và luồng chặn với thành viên phụ trách feed/chat.

## 7. Checklist nghiệm thu

- Hồ sơ riêng hiện thông tin cá nhân; hồ sơ người khác không làm lộ email/ngày sinh từ cache của chính mình.
- Sửa hồ sơ có validation; báo lỗi server; không báo lưu thành công trước response.
- A gửi B → B nhận → B chấp nhận → cả hai thấy bạn và thống kê cập nhật; kiểm thử riêng từ chối và hủy bạn.
- Không tự kết bạn/theo dõi/chặn chính mình; không kết bạn khác vai trò; xử lý thao tác lặp và quan hệ đã thay đổi trên thiết bị khác.
- A follow B → danh sách following của A và followers của B đồng bộ; bỏ follow cập nhật lại.
- A chặn B → hủy bạn/follow, hồ sơ bị hạn chế; kiểm thử feed/chat với module liên quan; bỏ chặn không tự khôi phục bạn bè.
- Tìm kiếm có dữ liệu/rỗng/lỗi, tải thêm đúng, truy vấn cũ không ghi đè truy vấn mới; Enter ghi lịch sử, gõ trực tiếp không ghi; xóa đúng saved_search_id.
- Loading, mất mạng, hết phiên, thử lại và điều hướng quay lại không gây thao tác trùng hoặc cập nhật widget đã dispose.

Điều kiện còn thiếu để xác nhận tích hợp: tài khoản thử hợp lệ, interface Auth/router/media của nhóm và response thật cho các trường quan hệ chưa đủ rõ. Các điểm này không cản trở việc dựng DTO, repository và giao diện bằng dữ liệu giả được gắn nhãn rõ ràng.
