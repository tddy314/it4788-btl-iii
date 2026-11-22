# PRODUCT BACKLOG – THÀNH VIÊN 5

> Cập nhật 18/11/2026: đây là kế hoạch nội bộ, không phải đặc tả nguyên văn của thầy. Tham chiếu slide/JSON bên dưới có chỗ dùng tên trường và kiểu cũ; PDF thực tế có 208 trang. Dùng [đối chiếu PDF–Swagger hiện tại](doi-chieu-pdf-swagger-2026-11-18.md) và OpenAPI làm căn cứ triển khai. Những đề xuất optimistic read, tài nguyên GIF có sẵn hoặc tự retry không phải yêu cầu PDF. Mã thành công thực tế đã xác nhận trước đây là `1000`, không dùng ví dụ `0000` để thay cấu hình.
> **Dự án:** SQB (Social Network for Student-Generated Question Bank) – Bài tập lớn IT4788  
> **Phạm vi trách nhiệm:** `features/chat`, `features/notifications`, Cài đặt thông báo & Quản trị thiết bị trong `features/settings`  
> **Tài liệu căn cứ:** PDF đặc tả bài tập lớn (208 trang), `AGENTS.md`, `docs/doi-chieu-pdf-swagger-2026-11-18.md`
> **Nguyên tắc cốt lõi:** Nghiệm thu kiểm tra mất mạng bắt buộc của giảng viên (Bảo toàn draft, chống gửi duplicate, cache offline, đồng bộ an toàn).

---

## 1. TỔNG QUAN PHÂN RÃ THEO MÔ HÌNH MOSCOW

| User Story ID | Tên chức năng | Độ ưu tiên | Story Points | Tham chiếu Slide PDF |
| :---: | :--- | :---: | :---: | :---: |
| **US-01** | Tab Danh sách thông báo & Badge số tin chưa đọc | **Must Have (P0)** | **5** | Trang 193, 194 |
| **US-02** | Đánh dấu đã đọc thông báo (Từng mục & Đọc tất cả) | **Must Have (P0)** | **3** | Trang 195, 196 |
| **US-03** | Điều hướng Deep Link từ thông báo đến đúng màn hình | **Should Have (P1)** | **5** | Trang 26, 194 |
| **US-04** | Cache offline danh sách thông báo & Xử lý mất mạng | **Must Have (P0)** | **3** | Trang 35, 36 |
| **US-05** | Danh sách cuộc trò chuyện gần nhất (Conversations List) | **Must Have (P0)** | **5** | Trang 180, 181 |
| **US-06** | Mở / Khởi tạo cuộc trò chuyện 1–1 với người dùng khác | **Must Have (P0)** | **3** | Trang 182 |
| **US-07** | Màn hình hội thoại & Tải lịch sử tin nhắn (Reverse Scroll) | **Must Have (P0)** | **5** | Trang 183, 184 |
| **US-08** | Gửi tin nhắn text, lưu nháp (Draft) & Chống gửi trùng lặp | **Must Have (P0)** | **8** | Trang 28, 36, 189 |
| **US-09** | Chèn cảm xúc (Emote bằng ký tự) & Không cho phép tag người | **Must Have (P0)** | **2** | Trang 28 |
| **US-10** | Chụp ảnh camera & Gửi ảnh trong chat (`purpose=CHAT`) | **Should Have (P1)** | **5** | Trang 28, 157 |
| **US-11** | Nhắn tin Realtime qua STOMP WebSocket & Đang gõ (Typing) | **Should Have (P1)** | **8** | Trang 6, 189–192 |
| **US-12** | Đồng bộ trạng thái đã đọc tin nhắn (`/app/chat.read`) | **Should Have (P1)** | **3** | Trang 191 |
| **US-13** | Xử lý kịch bản Ngắt mạng & Reconnect phục hồi trong Chat | **Must Have (P0)** | **5** | Trang 35, 36 |
| **US-14** | Màn hình Cài đặt thông báo Push & Tùy chọn âm thanh độc lạ | **Should Have (P1)** | **5** | Trang 26, 29, 197–200 |
| **US-15** | Đăng ký & Hủy thiết bị nhận Push (Device FID / FCM) | **Could Have (P2)** | **5** | Trang 86, 87, 198 |

---

## 2. CHI TIẾT CÁC USER STORIES (BACKLOG ITEMS)

### PHẦN I: HỆ THỐNG THÔNG BÁO (`features/notifications`)

#### 🔹 US-01: Tab Danh sách thông báo & Badge chưa đọc
* **Mô tả:** Là một sinh viên, tôi muốn mở tab Thông báo trên thanh điều hướng dưới để xem danh sách các tương tác liên quan đến mình và biết có bao nhiêu thông báo mới chưa đọc.
* **API Hợp đồng (Slide 193, 194):**
  * Endpoint: `GET /notifications`
  * Query parameters: `limit` (mặc định 20), `after` (cursor phân trang).
  * Envelope Response: `{ code: "0000", message: "Success", data: { items: [...], unread_count: "3", pagination: { after: "cursor_id", has_next: true } } }`
  * Cấu trúc mỗi Notification item:
    * `notification_id`: String
    * `type`: String (e.g. `POST_LIKE`, `POST_COMMENT`, `FRIEND_REQUEST`, `SESSION_APPROVED`, `NEW_MESSAGE`)
    * `title`: String
    * `body`: String
    * `icon_url`: String (optional)
    * `read_at`: String (null nếu chưa đọc)
    * `created_at`: String (ISO timestamp)
    * `actor`: `{ user_id, full_name, avatar_url, frame_url }`
    * `target`: `{ type, id, url }`
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Gắn vào `AppTab.notifications` trong `AppShell`.
  2. Hiển thị danh sách item: Avatar người gửi (hỗ trợ khung frame avatar nếu có), nội dung thông báo, thời gian tương đối (vd: "5 phút trước", "Hôm qua").
  3. Phân biệt trực quan giữa thông báo **chưa đọc** (nền nổi bật, chữ in đậm) và **đã đọc**.
  4. Hỗ trợ Pull-to-refresh và cuộn xuống để tải thêm (Infinite Scroll) mượt mà.
  5. Đầy đủ các trạng thái giao diện chuẩn: `AppLoadingState`, `AppEmptyState`, `AppErrorState` (kèm nút Thử lại).

---

#### 🔹 US-02: Đánh dấu đã đọc thông báo (Từng mục & Đọc tất cả)
* **Mô tả:** Là một sinh viên, tôi muốn khi bấm vào một thông báo chưa đọc thì nó chuyển sang trạng thái đã đọc, hoặc có nút "Đánh dấu tất cả là đã đọc" để xóa toàn bộ cờ chưa đọc.
* **API Hợp đồng (PDF trang 196, 197; kiểu dữ liệu lấy Swagger hiện tại):**
  * `POST /notifications/{id}/read` $\rightarrow$ Trả về `unread_count` mới.
  * `POST /notifications/read-all` $\rightarrow$ Đánh dấu toàn bộ là đã đọc, trả về `data: null`.
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Khi nhấn vào thông báo chưa đọc:
     * Gửi request `POST /notifications/{id}/read`; chỉ cập nhật UI sau xác nhận, dùng `read`, `read_at`, `unread_count` trong response Swagger. PDF trang 196 dùng tên cũ `is_read` và không bắt buộc Optimistic Update.
     * Lỗi giữ trạng thái đã biết; timeout chỉ đối soát GET, không tự gửi lại POST. GET cũ không ghi đè biên nhận mới.
  2. Nút "Đánh dấu tất cả đã đọc" trên AppBar:
     * Gọi `POST /notifications/read-all` và chuyển toàn bộ danh sách đã đọc khi server xác nhận (`data: null`).
     * Chặn bấm liên tục (debounce/disable button) khi đang trong quá trình gửi request.

---

#### 🔹 US-03: Điều hướng Deep Link từ thông báo đến đúng màn hình
* **Mô tả:** Là một người dùng, khi nhấn vào một thông báo, tôi muốn ứng dụng tự động mở đúng bài viết, chi tiết bộ câu hỏi, cuộc trò chuyện hoặc trang cá nhân tương ứng.
* **Quy tắc điều hướng (Slide 26 & 194):**
  * `target.type == "POST"` $\rightarrow$ Mở màn hình chi tiết bài viết (`AppRoutes.postDetail`).
  * `target.type == "SESSION"` $\rightarrow$ Mở chi tiết đề xuất câu hỏi trong `features/question_bank` khi có quyền. `QUESTION` cần ID phiên để tới câu cụ thể; nếu thiếu thì vào Ngân hàng câu hỏi với thông báo hướng dẫn, không đoán ID.
  * `target.type == "CONVERSATION"` $\rightarrow$ Mở màn hình chat theo `target_id`.
  * `target.type == "USER"` $\rightarrow$ Mở hồ sơ theo `target_id`. Các tên cũ `CHAT`, `MESSAGE`, `QUESTION_SESSION` chỉ là alias tương thích, không phải enum Swagger hiện tại.
* **Xử lý ngoại lệ an toàn:**
  * Nếu nội dung đích đã bị tác giả xóa (API trả về HTTP 404 hoặc 403): Hiển thị SnackBar thông báo tiếng Việt: *"Nội dung này không còn tồn tại hoặc bạn không có quyền xem"*, giữ nguyên màn hình hiện tại, **tuyệt đối không để ứng dụng crash**.

---

#### 🔹 US-04: Cache offline danh sách thông báo & Xử lý mất mạng
* **Mô tả:** Khi giảng viên ngắt mạng kiểm tra bài tập lớn, mở tab thông báo vẫn phải hiển thị danh sách đã lưu trước đó, không được hiện màn hình lỗi trắng xóa.
* **Kỹ thuật tích hợp (Slide 35, 36 & AGENTS.md):**
  * Lưu qua `DraftStore` bảo mật theo `userId`, tối đa 30 mục/512 KiB; chuyển record `JsonCache` cũ khi đọc, không ghi nội dung riêng tư vào preferences.
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Khi offline, mở tab thông báo: Đọc dữ liệu từ cache cục bộ và hiển thị đầy đủ kèm `ConnectionBanner` báo trạng thái mất mạng.
  2. Kéo làm mới (pull-to-refresh) lúc mất mạng: Giữ nguyên danh sách cũ, hiện thông báo lỗi nhẹ ở góc dưới, **không xóa dữ liệu đã hiển thị**.
  3. Khi đổi tài khoản (Logout user A $\rightarrow$ Login user B): Xóa/tách biệt hoàn toàn cache của user A, không hiển thị dữ liệu lẫn lộn.

---

### PHẦN II: TRÒ CHUYỆN 1–1 (`features/chat`)

#### 🔹 US-05: Danh sách cuộc trò chuyện gần nhất (Conversations List)
* **Mô tả:** Là một sinh viên, tôi muốn xem danh sách các cuộc trò chuyện gần đây kèm tin nhắn mới nhất và thời gian gửi để nhanh chóng trao đổi bài vở.
* **API Hợp đồng (Slide 180, 181):**
  * Endpoint: `GET /conversations?limit=20&after={cursor}`
  * Envelope Response: `{ code: "0000", message: "Success", data: { items: [...], pagination: { after, has_next } } }`
  * Cấu trúc mỗi Conversation item:
    * `conversation_id`: String
    * `type`: `DIRECT` (hoặc `GROUP` - phạm vi bài tập lớn chỉ dùng `DIRECT`)
    * `display_name`: String
    * `display_avatar_url`: String
    * `last_message`: `{ id: String, content: String }`
    * `unread_count`: String / Int
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Nút mở danh sách tin nhắn từ biểu tượng tin nhắn trên AppBar của màn hình chính.
  2. Hiển thị Avatar (`AppAvatar`), tên bạn chat, trích đoạn tin nhắn gần nhất, thời gian và số tin chưa đọc.
  3. Hỗ trợ cache danh sách hội thoại: Mất mạng vẫn mở xem được danh sách đã lưu trên máy.

---

#### 🔹 US-06: Mở / Tạo cuộc trò chuyện 1–1 với bạn học
* **Mô tả:** Bấm vào nút "Nhắn tin" từ trang cá nhân hoặc danh sách bạn bè để bắt đầu trò chuyện trực tiếp 1–1.
* **API Hợp đồng (Slide 182):**
  * Endpoint: `POST /conversations/direct`
  * Body theo Swagger: `{ "target_user_id": 123 }` (số nguyên).
  * Response: `{ conversation_id: "99", type: "DIRECT", members: [...] }`
* **Xử lý đặc biệt (Slide 24 & AGENTS.md):**
  * Nếu hai người **đã chặn (block) nhau**: Màn hình chat phải hiển thị thông báo *"Bạn không thể gửi tin nhắn cho người này"* và khóa hoàn toàn ô nhập văn bản.

---

#### 🔹 US-07: Màn hình hội thoại & Tải lịch sử tin nhắn (Reverse Scroll)
* **Mô tả:** Hiển thị tin nhắn trong cuộc trò chuyện theo dạng bong bóng chat hai bên và cuộn ngược lên trên để tải thêm tin cũ hơn.
* **API Hợp đồng (Slide 183, 184):**
  * Endpoint: `GET /conversations/{id}/messages?limit=20&after={cursor}`
  * Cấu trúc mỗi Message item:
    * `message_id`: String
    * `sender_id`: String
    * `sender_name`: String
    * `avatar_url`: String
    * `content`: String
    * `message_type`: String (`TEXT`, `IMAGE`)
    * `media_urls`: List<String>
    * `created_at`: String
    * `read_by`: List<Object>
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Giao diện bong bóng tin: Tin của mình ở bên phải (`AppColors.primary`), tin đối phương ở bên trái.
  2. Cuộn lên trên để tải tin cũ hơn (Reverse Infinite Scroll), giữ vị trí cuộn ổn định không bị giật trang.
  3. Mở cuộc trò chuyện sẽ tự động gọi API/STOMP đánh dấu đã đọc.

---

#### 🔹 US-08: Gửi tin nhắn text, lưu nháp (Draft) & Chống gửi trùng lặp
* **Mô tả:** Soạn và gửi tin nhắn; nếu thoát ứng dụng đột ngột thì văn bản đang gõ không bị mất; không gửi trùng lặp tin nhắn khi thử lại.
* **Quy chuẩn bắt buộc (Slide 28, 36 & AGENTS.md):**
  * Kiểm tra hợp lệ dữ liệu ở client trước khi kiểm tra mạng (Slide 36).
  * Lưu trữ nháp bằng `DraftStore` (tồn tại qua các lần tắt/mở lại app).
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. **Lưu bản nháp:** Đang gõ dở văn bản mà nhấn Back hoặc tắt app $\rightarrow$ Mở lại cuộc trò chuyện, văn bản vẫn nằm nguyên trong ô nhập. Chỉ xóa draft khi tin nhắn đã được gửi thành công lên server.
  2. **Trạng thái gửi (Optimistic UI):**
     * Tin nhắn vừa gửi xuất hiện ngay trong khung chat với icon đồng hồ ("Đang gửi").
     * Server xác nhận thành công $\rightarrow$ Chuyển sang "Đã gửi".
     * Lỗi mạng/timeout $\rightarrow$ Hiển thị dấu chấm than đỏ ("Lỗi gửi - Chạm để thử lại").
  3. **Chống Replay Request:** Gán `client_msg_id` để theo dõi cục bộ, nhưng chưa xác nhận backend echo/chống trùng bằng trường này. Kết quả gửi chưa rõ phải ở `unconfirmed` và đối soát bằng lịch sử; không replay tin/upload dựa vào giả định UUID bảo đảm chống trùng ở server.
  4. Vô hiệu hóa nút gửi khi ô nhập rỗng hoặc chỉ toàn khoảng trắng.

---

#### 🔹 US-09: Chèn cảm xúc (Emote bằng ký tự) & Không cho phép tag người
* **Mô tả:** Cho phép chèn cảm xúc bằng các ký tự đặc biệt, đồng thời tuân thủ quy định **không hỗ trợ tag tên** trong chat.
* **Quy định từ Slide 28 của giảng viên:**
  * *"Không cho phép tag thành viên khác vào bài viết hoặc đoạn chat hoặc bình luận"*
  * *"Cho phép chèn các emotion trong bài viết hoặc bình luận hoặc tin nhắn chat bằng cách nhập các ký tự đặc biệt"*
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Tự động chuyển đổi các ký tự cảm xúc thông dụng (vd: `:)`, `:D`, `:(`, `<3`, `:))`) thành emoji hoặc biểu tượng tương ứng trong bong bóng chat.
  2. Không hiện danh sách gợi ý tag `@username` khi gõ ký tự `@` trong ô chat.

---

#### 🔹 US-10: Chụp ảnh camera & Gửi ảnh trong chat
* **Mô tả:** Chụp ảnh trực tiếp từ camera hoặc chọn ảnh từ thư viện để gửi trong cuộc trò chuyện.
* **Quy định từ Slide 28, 157 của giảng viên:**
  * Chụp ảnh trong app (Camera) hoặc chọn ảnh có sẵn trong máy.
  * Upload qua API: `POST /medias/upload?purpose=CHAT` (ảnh tối đa 4MB).
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Tích hợp nút đính kèm ảnh: Chọn "Chụp ảnh từ Camera" hoặc "Chọn từ Thư viện".
  2. Validate dung lượng ảnh trước khi upload ($\le 4\text{MB}$); nếu vượt quá, báo lỗi tiếng Việt cụ thể.
  3. Hiển thị thanh tiến trình upload (%) trực tiếp trên bong bóng ảnh đang gửi.
  4. Hiển thị ảnh nhận được bằng `AppNetworkImage`, bấm vào ảnh để xem toàn màn hình.

---

#### 🔹 US-11: Nhắn tin Realtime qua STOMP WebSocket & Trạng thái Đang nhập
* **Mô tả:** Nhận tin nhắn mới tức thời qua WebSocket và hiển thị trạng thái khi đối phương đang soạn thảo.
* **Hợp đồng STOMP (Slide 189–192):**
  * Handshake WSS: `wss://snsqb.duckdns.org/api/v1/ws` (Header: `Authorization: Bearer <token>`).
  * Lắng nghe tin mới: Subscribe `/user/queue/messages`.
  * Gửi tin: `SEND /app/chat.send` với body `{ conversation_id, content, message_type: "TEXT"|"IMAGE", media_urls: [...] }`.
  * Swagger hiện tại: `SEND /app/chat.typing` với `{ conversation_id: 1, typing: true/false }`. Nhận typing/read/message qua `/user/queue/messages`; không phát payload/topic cũ trong PDF lên server hiện tại.
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Kết nối STOMP sau khi đăng nhập và tự động ngắt khi đăng xuất.
  2. Nhận tin nhắn mới: Tin nhắn mới xuất hiện ngay lập tức và tự cuộn xuống đáy màn hình.
  3. Typing indicator: Hiển thị 3 chấm chuyển động hoặc chữ *"Đối phương đang soạn tin..."* khi nhận sự kiện typing từ kênh socket, tự biến mất sau 3 giây không có cập nhật.
  4. Hủy subscription khi rời màn hình chat để giải phóng bộ nhớ.

---

#### 🔹 US-12: Đồng bộ trạng thái đã đọc tin nhắn
* **Mô tả:** Báo cho server và đối phương biết mình đã đọc tin nhắn đến mốc nào.
* **API Hợp đồng (Slide 191):**
  * `SEND /app/chat.read` với payload theo Swagger: `{ "conversation_id": 1, "message_id": 123 }`.
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Khi người dùng mở màn hình hội thoại hoặc cuộn tới tin nhắn mới: Tự động phát sự kiện đọc qua WebSocket.
  2. Hiển thị chữ "Đã xem" nhỏ dưới tin nhắn cuối cùng do mình gửi khi đối phương đã đọc.

---

#### 🔹 US-13: Nghiệm thu Mất mạng & Reconnect phục hồi trong Chat
* **Mô tả:** Kịch bản kiểm tra của giảng viên: Khi ngắt kết nối mạng hoặc đổi sang chế độ máy bay, màn hình chat không bị crash, tin nhắn offline được lưu lại và tự đồng bộ khi có mạng trở lại.
* **Quy định từ Slide 35, 36 & AGENTS.md:**
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Mở app ở chế độ máy bay: Đọc lại toàn bộ lịch sử tin nhắn đã cache từ trước.
  2. Đang gửi tin nhắn thì mất mạng: Không treo spinner vô hạn; hiển thị ngay banner offline và biểu tượng "Gửi thất bại" cạnh tin nhắn.
  3. Bật lại mạng: kết nối lại có kiểm soát khi foreground/thử lại hoặc nhận thay đổi mạng; không vòng lặp reconnect vô hạn, không tự phát lại thao tác ghi.
  4. Đồng bộ lại lịch sử tin nhắn mới từ server, đối soát bằng `message_id` để loại bỏ tin nhắn trùng lặp.
  5. Mất mạng **không được tự ý logout** người dùng.

---

### PHẦN III: CÀI ĐẶT THÔNG BÁO & THIẾT BỊ (`features/settings`)

#### 🔹 US-14: Màn hình Cài đặt thông báo Push & Tùy chọn âm thanh độc lạ
* **Mô tả:** Cho phép sinh viên bật/tắt các loại thông báo và thiết lập âm thanh push notification theo yêu cầu đặc biệt của môn IT4788.
* **Yêu cầu riêng biệt cho IT4788 từ Slide 26 & 29 của thầy:**
  * *"Với IT4788: được phép tùy chọn âm thanh push notification sao cho thể hiện được trải nghiệm tốt nhất"*
  * *"Cho phép thiết lập tắt thông báo đẩy hoặc có thông báo đẩy nhưng dùng âm thanh mặc định (tiếng chuông vang lên) hoặc âm có tiếng nói (yêu cầu SV thu âm giọng nói để làm file phát ra)"*
* **API Hợp đồng (Slide 197–200):**
  * `GET /settings/push` & `PUT /settings/push`
  * Swagger hiện tại dùng boolean và key uppercase: `{ "push_enabled": true, "categories": { "SOCIAL": { "enabled": true }, "ACADEMIC": { "enabled": true }, "SYSTEM": { "enabled": true } }, "sound_enabled": true, "vibration_enabled": true }`; giữ `quiet_hours` và key khác không hiển thị. Không gửi `sound_type` ngoài schema.
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Màn hình Cài đặt thông báo gồm các Switch bật/tắt:
     * Tổng thể: Bật/tắt toàn bộ thông báo đẩy.
     * Từng chuyên mục: Mạng xã hội (tương tác, bạn bè), Học tập (ngân hàng câu hỏi), Hệ thống.
     * Rung (Vibration) & Âm thanh (Sound).
  2. **Tùy chọn âm thanh:** Mặc định hoặc giọng nói do sinh viên thu âm theo PDF trang 29; không thay yêu cầu thu âm bằng file có sẵn trong assets. Cần thử thu/phát và push chạy nền trên điện thoại thật.

---

#### 🔹 US-15: Đăng ký & Hủy thiết bị nhận Push (Device FID / FCM)
* **Mô tả:** Đăng ký định danh thiết bị lên hệ thống để nhận Push Notification và hủy đăng ký khi đăng xuất.
* **API Hợp đồng:** đối chiếu endpoint/schema thiết bị trong Swagger hiện tại; không suy đường dẫn từ tên slide cũ.
  * Theo Swagger hiện tại: `POST /devices/fid` với `{ "fid": "..." }` (Firebase Installation ID, không thay bằng FCM registration token).
  * `POST /devices/fid/unregister` với `{ "fid": "..." }` khi logout; không tự dùng DELETE hay endpoint `/devices/register` không có trong hợp đồng.
* **Tiêu chí nghiệm thu (Acceptance Criteria):**
  1. Tự động xin quyền thông báo trên Android (đặc biệt Android 13+ `POST_NOTIFICATIONS`).
  2. Gửi định danh thiết bị lên server sau khi đăng nhập thành công.
  3. Khi sinh viên bấm "Đăng xuất" (`session.clear()`): Gửi request hủy đăng ký thiết bị để tài khoản sau không nhận nhầm thông báo của người cũ.

---

## 3. KẾ HOẠCH PHÂN BỔ SPRINT (4 TUẦN)

* **Sprint 1 (Tuần 1):** Xây dựng Tab Thông báo (US-01, US-02), Cache Offline Thông báo (US-04), Khung Danh sách Hội thoại & Bắt đầu cuộc trò chuyện (US-05, US-06).
* **Sprint 2 (Tuần 2):** Màn hình Chat chi tiết (US-07), Gửi tin nhắn Text & Lưu nháp (US-08), Chèn cảm xúc (US-09), Upload ảnh trong Chat (US-10), Deep link thông báo (US-03).
* **Sprint 3 (Tuần 3):** Tích hợp Realtime STOMP WebSocket (US-11), Đã đọc tin nhắn (US-12), Màn hình Cài đặt thông báo & Tùy biến âm thanh (US-14), Đăng ký Device (US-15).
* **Sprint 4 (Tuần 4):** Xử lý ngắt mạng & Reconnect phục hồi tin nhắn (US-13), Test nghiệm thu trên 2 thiết bị thật theo kịch bản của giảng viên.

---

## 4. DEFINITION OF DONE (DOD) CHO THÀNH VIÊN 5
Mọi User Story chỉ được coi là hoàn tất khi:
1. **Kiến trúc & Độc lập:** Chỉ viết code trong `lib/features/chat`, `lib/features/notifications` và phần settings tương ứng. Tuyệt đối không tự ý sửa core chung.
2. **Offline & Bảo vệ dữ liệu:** Mất mạng không gây crash, bản nháp (draft) được lưu giữ bền vững, có banner cảnh báo trạng thái mạng tiếng Việt rõ ràng.
3. **Chống Replay Request:** Các thao tác gửi tin nhắn và đánh dấu đã đọc không gửi lặp khi mạng chập chờn.
4. **Code Quality:** Đã chạy `dart format lib test` và `flutter analyze` đạt 0 cảnh báo/lỗi lint.
