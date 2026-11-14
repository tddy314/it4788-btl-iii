# Hồ sơ và quan hệ bạn bè

Cập nhật 04/11/2026. Đã nối UI/repository theo OpenAPI công khai tải từ server trong lượt triển khai này. Chưa kiểm chứng request xác thực bằng tài khoản thật; test dùng transport/storage giả. Tài liệu phạm vi cũ `pham-vi-module-ho-so-quan-he-tim-kiem.md` là kế hoạch rộng hơn, không phải hiện trạng của repo.

## Màn hình đã có

- Phạm vi đã xác nhận: hồ sơ và quan hệ bạn bè. Tìm người chỉ là luồng hỗ trợ kết bạn trong tab Bạn bè; không làm module tìm kiếm toàn cục, tìm bài viết, lịch sử và từ khóa thịnh hành.
- Tab **Cá nhân**: hồ sơ của tôi, ảnh đại diện/bìa, giới thiệu, thống kê, chỉnh sửa; nút **Cài đặt** giữ luồng đổi mật khẩu/đăng xuất cũ.
- Tab **Bạn bè**: danh sách bạn, lời mời nhận/gửi, đang theo dõi, người theo dõi và danh sách chặn. Có kéo tải lại, tải thêm theo cursor server, chống trùng ID, trạng thái rỗng/lỗi.
- Hồ sơ người khác mở từ danh sách; gửi lời mời, hủy bạn, theo dõi/bỏ theo dõi, xác nhận chặn. Chấp nhận/từ chối nằm ở danh sách lời mời nhận để không suy đoán chiều của `PENDING`.
- Danh sách chặn mở được từ hồ sơ của tôi và cài đặt. Bỏ chặn không gọi lại API kết bạn/follow.
- Tab Bạn bè có **Tìm bạn bè**: nhập tên → danh sách người dùng → mở hồ sơ → kết bạn/theo dõi. Không có nút tìm kiếm toàn cục trên hồ sơ cá nhân.
- Danh sách bài viết và phiên đề xuất của hồ sơ ở dạng tóm tắt chỉ đọc, phân trang riêng. `RESOLVED` hiển thị **Đã xử lý**, không khẳng định duyệt mọi câu. Không hiển thị nguồn tự làm/AI.
- Chỉnh sửa tên, tiểu sử, giới tính, ngày sinh, múi giờ, ảnh đại diện/bìa. Không chỉnh email/mã sinh viên/vai trò, không tự xóa tài khoản. Trường tùy chọn rỗng được bỏ qua, ngoại trừ tiểu sử có thể gửi chuỗi rỗng; chưa giả định null sẽ xóa dữ liệu.

## Tích hợp và thành phần dùng lại

Giữ nguyên implementation `lib/app`, `lib/core`, theme và Android config. `AuthApplication` đăng ký builders cho `AppTab.profile`, `AppTab.friends`, route `/profile/user` và bổ sung danh sách chặn vào composition của cài đặt. Ví dụ từ module bài viết/tìm kiếm:

```dart
Navigator.pushNamed(context, ProfileRoutes.user, arguments: userId.toString());
```

`SocialChanges` thuộc feature, sống cùng composition và theo dõi phiên. Các màn/repository giữ `SocialLease`: logout/đổi tài khoản làm lease cũ mất hiệu lực, kể cả logout rồi đăng nhập lại cùng ID. Token refresh không vô hiệu lease. Mutation được khóa chung, phát `revision` để các danh sách/hồ sơ bỏ response cũ và tải lại; sự kiện `lastBlockedUserId` là điểm nối để feed/chat sau này bỏ dữ liệu tương ứng. Feed/chat chưa được tích hợp sự kiện này vì hiện chưa có implementation.

`FriendFinderScreen`/`FriendFinderController`/`FriendFinderRepository` nằm trong `features/relationships`, route `RelationshipRoutes.findFriends`. Chỉ GET `search` với `type: USER`, `limit: 20`, `after` là offset do server trả; không dùng ID/timestamp làm offset. Không có tham số lựa chọn loại thực thể khác. Từ khóa phải có nội dung, UI giới hạn 200 ký tự; không áp minLength 2 của API ghi lịch sử cho GET tìm người. Gõ có debounce 350 ms, Enter tìm ngay, đổi từ khóa hủy/bỏ kết quả cũ. Refresh cùng từ khóa khi mất mạng giữ kết quả RAM; đổi từ khóa không tái sử dụng kết quả của từ khóa trước. Không ghi/cache lịch sử, không giữ email/mã sinh viên, không lưu marker tìm kiếm. Không tạo API client/token store khác.

Tái sử dụng `AppScope`, `ApiClient`, `SessionStore`, `JsonCache`, `DraftStore`, `MediaUploadService`, `AppAvatar`/`AppNetworkImage`, widget trạng thái/nút và theme. Chỉ thêm `image_picker` để chọn ảnh từ thư viện, không tạo HTTP client/token store khác. Bộ upload dùng purpose `AVATAR`/`COVER` theo Swagger; file được kiểm tra dung lượng trước đọc vào RAM và decode ảnh thật trước upload. Giới hạn 4 MiB, có tiến trình/hủy khi dispose.

## Hợp đồng đã đọc

Nguồn: `https://snsqb.duckdns.org/api/v1/docs/openapi.json`. Endpoint dùng Bearer token qua client chung, không gọi admin.

| Luồng | Endpoint và mapping |
| --- | --- |
| Hồ sơ | `GET users/me`, `PUT users/me`, `GET users/{userId}`; cập nhật chỉ trường người dùng thực sự sửa |
| Thống kê | `GET users/{userId}/relationship-stats`; `counts`, `relationship_with_me.friend/following/followed_by/blocked/friend_request_status` |
| Danh sách | `GET friendships`, `friendships/requests/received`, `friendships/requests/sent`, `follows/following`, `follows/followers`, `blocks`; `items`, `pagination.after`, `pagination.has_next` |
| Lời mời | `POST friendships/request` với `addressee_id`; accept/decline với `requester_id`; đọc người nhận từ `receiver`, người gửi từ `requester` |
| Hủy bạn | `DELETE friendships/{friendId}`; không dùng API này để tự suy ra thao tác hủy lời mời gửi |
| Follow | `POST/DELETE follows/{targetUserId}`; xác nhận target ID và flag `following` trong response |
| Chặn | `POST/DELETE blocks/{targetUserId}`; xác nhận target ID và flag `blocked` |
| Nội dung | `GET users/{userId}/posts` dùng `items`; `GET users/{userId}/sessions` dùng `contents`; cursor của hai luồng là ID |
| Upload | `POST medias/upload?purpose=AVATAR/COVER`, multipart `file`; kiểm tra response media là ảnh |
| Tìm người để kết bạn | `GET search?query=...&type=USER&limit=20`; wrapper `type` + `user`, phân trang offset |

Mã thành công vẫn là `1000` theo cấu hình chung đã xác nhận trước đó. Không dùng ví dụ `0000` của Swagger. Các khác biệt giữa response xác thực thật và schema của module này còn cần kiểm chứng.

## Offline, bản nháp và đối soát

- Hồ sơ của tôi lưu đúng **một** bản tóm tắt công khai theo user trong preferences: tên, ảnh, bio, vai trò, số đếm. Không lưu email, ngày sinh, mã sinh viên hoặc quan hệ riêng tư ở đây. Khi mở lại offline, hiện bản tóm tắt đã lưu; chỉnh sửa yêu cầu tải được hồ sơ đầy đủ trước.
- Hồ sơ người khác và danh sách quan hệ/nội dung chỉ giữ trong RAM, không cache đồ thị xã hội trên đĩa. Refresh thất bại do mạng giữ nội dung đang có, khóa thao tác dựa trên dữ liệu lỗi; 401/403/404 ẩn nội dung tương ứng. Đóng process không khôi phục các danh sách này.
- Bản nháp chỉnh sửa dùng secure `DraftStore`, tách user, lưu sau thay đổi 500 ms, trước picker/lưu, khi app nền và rời màn. Hàng đợi lưu ngăn bản nháp cũ ghi sau lần lưu mới. Chỉ bỏ draft sau response cập nhật được xác nhận. Lỗi lưu draft có thông báo, không giả vờ đã lưu bền vững.
- Ảnh đã upload được giữ bằng URL trong draft. Ảnh mới chọn còn là file tạm: không bảo đảm phục hồi nếu Android hủy process trong picker/upload. Sau lỗi, giữ nội dung văn bản và ảnh tạm nếu còn; không tự upload lại. Người dùng có thể chọn lại hoặc bỏ ảnh chưa được xác nhận trước khi lưu. Cache ảnh có thể bị hệ thống dọn.
- Mọi thao tác quan hệ đều có GET đối soát trước write, kể cả bấm lại sau timeout. Accept/decline kiểm tra danh sách lời mời nhận; chặn/bỏ chặn kiểm tra danh sách chặn của chính mình. Dừng nếu cursor lặp hoặc vượt 50 trang đối soát. Request gửi có thể trả `ACCEPTED`; không tự gán `PENDING`. Kiểm tra vai trò bằng hồ sơ trước khi gửi lời mời.
- Lưu hồ sơ validate trước mạng, GET hồ sơ hiện tại rồi chỉ PUT các trường đã sửa và còn khác server. Nếu PUT trước đã được xử lý nhưng mất response, lần bấm tiếp sẽ không PUT lại cùng giá trị. Không tự replay write/upload, không polling khi mạng trở lại.
- Dispose hủy request và bỏ response cũ. Làm mới do mutation có generation riêng để trang cũ không ghi đè danh sách mới. Chặn sẽ loại nội dung cũ trước khi đọc lại quyền.

## Kiểm tra và giới hạn

- `flutter pub add image_picker` hoàn tất, đã cập nhật lockfile.
- `flutter analyze --no-pub`: không có issue; `git diff --check` sạch.
- Toàn bộ **60 test đạt**, gồm 18 test hồ sơ/quan hệ và 11 test tìm người trong Bạn bè: validation/DTO, bỏ qua trường không sửa, GET đối soát sau timeout PUT/accept, đồng cấp, chặn/bỏ chặn, khóa gửi lặp, logout/login cùng ID, cache không lưu thông tin riêng, phân trang/cursor lặp, response cũ/dispose, màn 320 px/font gấp đôi, giữ/khôi phục draft và giữ danh sách khi thao tác offline thất bại. Test tìm người kiểm tra luôn dùng USER, không gọi lịch sử/ghi từ khóa, debounce, offset, kết quả cũ, offline, đổi phiên và luồng Bạn bè → tìm người → hồ sơ → gửi lời mời. Tất cả dùng transport/storage giả; chưa phải kiểm chứng backend thật.
- Đã thử build APK debug x86_64 với Gradle một worker, heap 1536 MiB. Build dừng ngay lúc khởi động Gradle với `java.io.IOException: Unable to establish loopback connection`; chưa xác nhận APK Android của module mới. NDK 28.2.13676358 và CMake 3.22.1 đã hiện diện khi kiểm tra.
- Chưa thử upload ảnh/quyền picker, hai tài khoản kết bạn/follow/chặn thật, Android thật, ngắt mạng giữa thao tác hoặc process death. Không tự dùng tài khoản/cấu hình server dùng chung để tạo dữ liệu thử.
- Chỉ giữ tìm người trong Bạn bè để mở hồ sơ và kết bạn. Phần tìm bài viết, lịch sử/thịnh hành, preview bài viết từ tìm kiếm và module `features/search` vừa thêm đã được bỏ theo phạm vi người dùng xác nhận. Màn đầy đủ của bài viết/phiên đề xuất, video viewer và chat vẫn chờ module tương ứng.

### Nghiệm thu thiết bị thật còn phải làm

1. Có hai tài khoản cùng vai trò: A gửi B, B nhận/chấp nhận hoặc từ chối, A/B refresh thấy số đếm và danh sách nhất quán; thử thao tác đồng thời trên hai máy.
2. Tắt mạng trước/trong PUT/upload/accept; kiểm tra input/draft, số request và trạng thái server sau khi nối lại. Không coi snackbar là bằng chứng server đã xử lý.
3. Chặn rồi bỏ chặn: quan hệ bạn/follow hai chiều mất, không tự hồi phục. Kiểm tra thêm feed/chat khi các module đó được nối.
4. Logout/đổi tài khoản trong lúc tải/upload/lưu; Back không mở nội dung cũ. Đóng/mở offline khôi phục đúng bản tóm tắt và draft theo user.
5. Chọn ảnh hỏng/rỗng/>4 MiB, hủy picker, quyền bị từ chối, file tạm mất, app nền/process bị hủy; kiểm tra giới hạn đã nêu ở trên.
6. Với tài khoản chưa có bạn: mở Tìm bạn bè, gõ tên, mở hồ sơ và gửi lời mời; ngắt mạng/đổi từ khóa khi đang tải, tải thêm và kiểm tra quyền sau chặn. Không được gọi API tìm bài viết hoặc lịch sử/thịnh hành trong luồng này.
