# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng placeholder dưới mỗi câu hỏi bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Đỗ Lê Việt Anh  Mã học viên: 2A202602491

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống mình thấy rõ nhất là lúc deploy lên Railway. Giả sử mình quên set
`AGENT_API_KEY` trong phần Variables. Nếu code để mặc định `"changeme"` thì app
vẫn khởi động bình thường, `/health` vẫn 200, Railway báo deploy thành công,
mình yên tâm đi ngủ. Nhưng lúc đó `/ask` đang được bảo vệ bằng một cái khóa mà
ai cũng đoán được (chỉ cần đọc repo public là thấy), nên bất kỳ ai cũng gọi
được và tiêu tiền LLM của mình — và mình chỉ biết khi nhìn hóa đơn.

Còn khi không có mặc định thì app chết ngay lúc khởi động. Mình đã thử chạy
container không truyền key: log báo `agent_api_key  Field required` rồi
`Application startup failed. Exiting.` Tức là lỗi hiện ra ngay lúc deploy, khi
mình còn đang nhìn màn hình, sửa một phút là xong. Chết sớm rẻ hơn nhiều so với
chạy "êm" mà sai.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Một dòng log mình thu được khi gọi `/ask`:

```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T08:35:07.086933+00:00", "user_id": "smoke", "tokens_in": 3, "tokens_out": 37, "cost_usd": 2.265e-05}
```

Hai việc làm được mà `print("đã trả lời xong")` chịu:

1. **Tính tiền theo user.** Vì mỗi dòng có sẵn `user_id` và `cost_usd`, công cụ
   log (Railway, Datadog...) có thể lọc `event = ask_completed` rồi cộng
   `cost_usd` theo từng `user_id` để biết hôm nay ai tiêu nhiều nhất. Với
   `print` thì không có user, không có số tiền, không biết đâu mà cộng.
2. **Đếm và cảnh báo.** Có `level` và `timestamp` chuẩn ISO nên mình đếm được
   số dòng `level = error` trong 5 phút gần nhất và đặt cảnh báo khi vượt
   ngưỡng, hoặc vẽ biểu đồ số request theo thời gian. Một chuỗi chữ tự do thì
   máy không phân tích được, chỉ người đọc được.

Thêm nữa, mỗi event nằm gọn trên một dòng nên hệ thống gom log không bị cắt
một log thành nhiều mảnh.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1730 MB (1.73 GB) |
| Multi-stage | 271 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Bản multi-stage nhỏ hơn khoảng 6,4 lần, chênh gần 1,46 GB. Phần chênh đó chủ
yếu là:

- **Base image đầy đủ `python:3.11`**: nó dựa trên Debian bản đầy đủ, kèm sẵn
  gcc, các công cụ build, header của hàng loạt thư viện hệ thống... Những thứ
  này chỉ cần lúc compile, còn lúc chạy app thì không dùng tới. Bản của mình
  dùng `python:3.11-slim` cho cả hai stage nên bỏ được phần lớn chỗ này.
- **Cache của pip**: bản cũ `pip install` không có `--no-cache-dir` nên file
  tải về vẫn nằm lại trong image. Bản mới cài ở stage `builder` rồi chỉ
  `COPY --from=builder /install` sang, cache và file tạm bị bỏ lại ở stage cũ.
- **Rác từ `COPY . .`**: bản cũ copy nguyên thư mục, gồm cả `.git`, tests,
  tài liệu... Bản mới chỉ copy `app/` và `utils/`, cộng với `.dockerignore`
  chặn `.git`, `.venv`, `.env`, tests.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Mình thêm đúng một dòng comment vào `app/main.py` rồi build lại bằng
`--progress=plain` để xem từng bước.

Với Dockerfile của mình, gần như tất cả đều `CACHED`: `COPY requirements.txt`,
`RUN pip install`, `COPY --from=builder`, `RUN useradd`, `WORKDIR`, `COPY utils`.
Chỉ có layer cuối `COPY app ./app` phải chạy lại vì đó là chỗ file bị đổi. Cả
lần build mất khoảng **2 giây**.

Mình thử lại y hệt với Dockerfile ban đầu (có `COPY . .` đứng trước
`RUN pip install`). Lần này `COPY . .` chạy lại vì một file trong thư mục đổi,
và vì Docker hủy cache từ layer đầu tiên thay đổi trở đi, nên `pip install`
cũng phải chạy lại từ đầu, mất **98,4 giây**; tổng cả lần build là **119 giây**.
Chỉ vì thêm một dòng comment mà phải cài lại toàn bộ thư viện. Đó là lý do
phải copy `requirements.txt` và cài dependency trước, copy code sau.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện mình hình dung như sau:

1. Code có lỗ hổng, ví dụ một thư viện dính lỗi deserialize hoặc một chỗ
   ghép chuỗi vào lệnh shell, cho phép kẻ tấn công chạy code tùy ý.
2. Code đó chạy với quyền của process app. Nếu container chạy root thì kẻ tấn
   công là root trong container: đọc/sửa mọi file, cài thêm công cụ, xem biến
   môi trường (trong đó có secret).
3. Từ root trong container, họ tìm đường thoát ra ngoài: một lỗi của kernel
   hoặc container runtime, một volume của host được mount vào, hay Docker
   socket bị mount nhầm. Vì container dùng chung kernel với host, root trong
   container thoát ra được thì thường thành root trên host luôn.

Lệnh `USER appuser` cắt chuỗi này ngay từ bước 2: process app chạy bằng user
thường (uid 10001 — mình đã kiểm tra bằng `whoami` trong image, ra `appuser`).
Kẻ tấn công chỉ có quyền của một user thường: không sửa được file hệ thống,
không cài package, và phần lớn các kỹ thuật thoát container cần quyền root nên
khó thành công hơn nhiều. Nếu có thoát được thì cũng chỉ là user thường trên
host chứ không phải root.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Tối đa **20 request trong 2 giây**. Cách làm: gửi 10 request lúc 10:00:59 (dùng
hết hạn mức của phút 10:00), rồi đợi qua giây 00 để bộ đếm reset, gửi tiếp 10
request lúc 10:01:01 (hạn mức của phút 10:01). Mỗi phút đều "đúng luật" nhưng
thực tế là 20 request trong khoảng 2 giây, gấp đôi hạn mức.

Sliding window không có kẽ hở này vì nó luôn đếm số request trong 60 giây gần
nhất tính từ thời điểm hiện tại, không có mốc reset cố định. Lúc test trên bản
deploy Railway, mình gọi 15 lần liên tiếp và nhận đúng 10 lần 200 rồi 5 lần 429,
trong Redis `ZCARD` của key rate limit cũng đúng bằng 10.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

Khác nhau ở thứ được đếm: **rate limit đếm số request** trong 60 giây gần nhất
(vượt thì trả 429), còn **cost guard đếm số tiền** đã tiêu trong tháng (vượt
ngân sách thì trả 402). Một cái chống spam/gọi quá nhanh, một cái chống cháy túi.

- **Rate limit cho qua nhưng cost guard chặn:** một user chỉ gửi 5 request mỗi
  phút (dưới hạn mức 10), nhưng mỗi request là một prompt rất dài, vài chục
  nghìn token, lại kéo theo lịch sử hội thoại. Số request thì ổn, nhưng tiền
  cộng dồn nhanh và chạm ngân sách tháng. Lúc test mình set sẵn chi tiêu của
  một user lên 999 USD, gọi `/ask` là nhận ngay
  `402 {"detail":"monthly budget exceeded"}`.
- **Rate limit chặn nhưng cost guard cho qua:** một script gửi 15 câu "test"
  ngắn trong 1 giây. Mỗi câu chỉ tốn khoảng 0,00002 USD nên ngân sách gần như
  không suy suyển, nhưng từ request thứ 11 trở đi đã bị 429 vì vượt 10
  request/phút.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Theo thứ tự:

1. Redis mất kết nối.
2. Endpoint gộp kiểm tra Redis nên trả lỗi trên **cả 3 container cùng lúc**, vì
   cả 3 dùng chung một Redis.
3. Orchestrator coi đây là liveness probe thất bại, nghĩa là "process hỏng",
   nên nó **restart cả 3 container**.
4. Trong lúc restart không còn container nào nhận request, toàn bộ user bị lỗi.
5. Container khởi động lại nhưng Redis vẫn chưa về, probe tiếp tục fail, lại bị
   restart, dễ rơi vào vòng lặp crash.
6. Sau 30 giây Redis quay lại, nhưng các container vẫn đang khởi động dở hoặc
   đang bị backoff giữa các lần restart, nên hệ thống còn chết thêm một lúc nữa.
   Một sự cố Redis 30 giây biến thành sự cố sập toàn bộ và kéo dài hơn.

Khi tách riêng thì khác hẳn. Mình đã thử `docker compose stop redis`: `/health`
vẫn trả 200 (process vẫn sống, không cần restart) còn `/ready` trả
`503 {"status":"not ready","redis":false}` (tạm đừng gửi traffic vào). Bật
Redis lại thì `/ready` tự về 200 mà không container nào bị restart.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Mình scale lên 3 container agent và gọi 6 lần với cùng `X-User-Id: scale`.
Request lần lượt rơi vào các container có IP `172.18.0.3`, `.4`, `.3`, `.5`,
`.3`, `.3` (cả 3 container đều được gọi tới), nhưng `history_length` vẫn tăng
đều: **0, 2, 4, 6, 8, 10**. Mỗi lượt thêm 2 message (câu hỏi + câu trả lời), và
container nào cũng thấy đủ lịch sử vì tất cả đọc chung một Redis.

Nếu lịch sử nằm trong dict Python thì mỗi container có một dict riêng trong RAM
của nó. Con số sẽ nhảy lung tung tùy request rơi vào container nào, kiểu
0, 0, 2, 0, 4, 6 thay vì tăng đều, và agent bị "mất trí nhớ" ngẫu nhiên. Tệ
hơn, restart container là dict mất sạch, về lại 0. Mình cũng đã thử restart
container agent: trước restart `history_length` là 2, sau restart gọi tiếp ra
4, tức là lịch sử vẫn còn nguyên nhờ nằm trong Redis.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

Lỗi mình gặp là lúc kiểm tra bản deploy trên Railway. `/health`, `/ready` và
`/ask` không có key đều đúng, nhưng khi gọi `/ask` có API key với câu hỏi
`"Deploy là gì?"` thì server trả:

```
HTTP/1.1 400 Bad Request
{"detail":"There was an error parsing the body"}
```

**Cách tìm nguyên nhân:** đầu tiên mình để ý là lỗi 400 chứ không phải 401,
nghĩa là API key đã được chấp nhận, lỗi nằm ở phần body. Cũng trong lúc đó,
vòng lặp 15 request với câu hỏi `"test"` (toàn chữ không dấu) lại chạy bình
thường, ra 10 lần 200 rồi 429. Khác biệt duy nhất là câu hỏi có tiếng Việt có
dấu. Mình đang chạy curl trong Git Bash trên Windows, và chuỗi tiếng Việt trong
tham số `-d '...'` bị đổi encoding trên đường đi, nên server nhận được byte
không phải UTF-8 hợp lệ và không parse được JSON.

**Cách sửa:** ghi body ra một file UTF-8 (kiểm tra bằng `xxd` thấy chữ "là" đúng
là `c3 a0`), rồi gửi bằng `--data-binary @body.json` kèm header
`Content-Type: application/json; charset=utf-8`. Lần này server trả 200 kèm câu
trả lời tiếng Việt đầy đủ. Như vậy server không có lỗi, lỗi nằm ở phía client
gửi request. Bài học: khi test API có dữ liệu Unicode trên Windows thì nên gửi
body từ file (hoặc dùng Python/Postman) thay vì gõ thẳng vào dòng lệnh.
