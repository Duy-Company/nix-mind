# Đề xuất chế độ Flow cho Nix Mind

Trạng thái: đề xuất để duyệt, chưa triển khai. Đợt phát triển hiện tại chỉ bổ sung style và nhãn trên các đường nối cha–con; không phát hành bản mới.

## Mục tiêu

Vẽ cách một tính năng hoạt động qua các màn hình, thao tác và điều kiện. Ví dụ:

```text
Màn A ── Bấm nút 1 ──→ Màn B
      └─ Bấm nút 2 ──→ Màn C
Màn B ── Lưu thành công ──→ Màn D
Màn C ── Tiếp tục ────────→ Màn D
Màn D ── Quay lại ────────→ Màn A
```

Chỉ đổi hình dạng đường hoặc hướng sắp xếp chưa thể diễn tả đầy đủ ví dụ này: cây mind map hiện tại chỉ cho mỗi node một cha và không có vòng lặp. Flow cần các đường chuyển tiếp độc lập với quan hệ cha–con.

## Vị trí setting và cách sử dụng

- Thêm **Sheet settings → Diagram type: Mind map / Flow**, áp dụng riêng từng sheet. Có thể tạo sheet Flow mới ngay từ nút thêm sheet.
- Trong Flow, chọn hướng bố cục **Left → Right** hoặc **Top → Bottom**. Mặc định Left → Right, đường vuông góc có mũi tên cuối.
- Các loại node: **Screen** (chữ nhật bo góc), **Decision** (hình thoi), **Start / End** (viên thuốc). Giữ nguyên các công cụ màu và chữ hiện có.
- Chọn node, dùng **Connect to…** để tạo đường đến một node đã có; kéo từ cổng nối là bước cải tiến tiếp theo. Không bắt người dùng nhân đôi Màn D chỉ để nối từ hai màn khác nhau.
- Nhãn đường diễn tả thao tác hoặc điều kiện: “Bấm đăng nhập”, “Yes”, “No”, “HTTP 200”, “Permission denied”. Có thể gợi ý Yes/No khi nối từ Decision; người dùng vẫn sửa được.
- Chọn đường để sửa nhãn, style, đổi đích hoặc xóa riêng đường. Xóa đường không xóa màn hình; xóa node cần xử lý rõ các đường liên quan.
- **Arrange** sắp xếp toàn sheet theo hướng đã chọn. Kéo node để chỉnh tay; đổi style/nhãn không tự sắp xếp hoặc đổi zoom/pan.

## Phạm vi MVP nên duyệt

1. Tạo sheet Flow riêng và lưu loại sơ đồ trong tài liệu.
2. Thêm Screen, Decision, Start/End; đặt node tự do.
3. Nối đến node mới hoặc đã có, nhiều đường vào một node, đường quay lại và self-loop.
4. Chỉnh nhãn/style trên từng đường bằng inspector Connection đã có.
5. Bố cục tự động theo hướng ngang/dọc; phân biệt các nhánh song song và đường quay lại để đọc được mũi tên/nhãn.
6. Save/Open và Undo/Redo đầy đủ cho node, đường nối và bố cục. Kiểm thử trước các trường hợp hội tụ, vòng lặp, xóa node và nhiều đường giữa cùng hai node.

Không đưa prototype tương tác, chạy mô phỏng luồng, ảnh chụp màn hình, swimlane hoặc sinh code vào MVP. Các ý tưởng này có thể mở rộng sau khi thao tác vẽ và đọc luồng đã thuận tiện.

## Dữ liệu và tương thích

- Giữ cây topic cho Mind map; bổ sung danh sách đường chuyển tiếp có ID, sourceID, targetID, style và nhãn cho Flow. Tách model đồ thị khỏi ràng buộc một root/một cha của mind map.
- Tái sử dụng dữ liệu style đường, nhưng không ép nhiều đường chuyển tiếp dùng chung style lưu trên một node.
- Nếu chuyển mind map sang Flow, tạo bản sao sheet, mỗi đường cha–con trở thành một đường chuyển tiếp; giữ nội dung và style để người dùng có thể so sánh. Không tự chuyển các tài liệu đang có.
- Không cho chuyển Flow bất kỳ về cây nếu có hội tụ/vòng lặp mà không giải thích dữ liệu nào không thể biểu diễn.
- Định dạng native phải lưu đủ dữ liệu Flow. Khi export sang định dạng cây không biểu diễn được đồ thị, báo rõ và yêu cầu chọn cách xuất; không âm thầm bỏ đường nối.

## Tiêu chí chấp nhận chính

Ví dụ Màn A → B/C → D → A ở trên phải vẽ được mà không nhân đôi màn hình. Chỉnh nhãn “Bấm nút 1”, Save/Open, Undo/Redo và Arrange đều giữ nguyên các đường chuyển tiếp. Hai sheet trong cùng file có thể dùng hai loại sơ đồ khác nhau.
