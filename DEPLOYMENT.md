# Thông Tin Deploy — Checkpoint 5

> Điền file này sau khi deploy xong. `pytest tests/test_cp5.py` đọc file này
> để tìm địa chỉ service của bạn và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị API key vào đây.**
> Repo này công khai — dán khóa vào là mất khóa.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Đỗ Lê Việt Anh |
| Mã học viên | 2A202602491 |
| Repo | https://github.com/dlvanh/K4-L3A-DAY12-DoLeVietAnh-2A202602491-CloudServicesAndDeployment |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://agent-production-218e.up.railway.app |
| Platform | Railway (project `day12-agent`, service `agent` build từ `Dockerfile` + service `Redis`) |
| Ngày deploy | 2026-09-28 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | platform tự gán |
| `AGENT_API_KEY` | ✅ | đặt trong Railway Variables, sinh ngẫu nhiên, không nằm trong repo |
| `REDIS_URL` | ✅ | Railway Redis — biến tham chiếu `${{Redis.REDIS_URL}}` |
| `RATE_LIMIT_PER_MINUTE` | ✅ | 10 |
| `MONTHLY_BUDGET_USD` | ✅ | 10.0 |
| `LOG_LEVEL` | ✅ | INFO |

## Lệnh Kiểm Tra

Thay `<URL>` bằng Public URL ở trên:

```bash
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i <URL>/health

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i <URL>/ready

# 3. Không có API key — mong đợi 401
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -d '{"question":"Hello"}'

# 4. Có API key — mong đợi 200 kèm câu trả lời
curl -i -X POST <URL>/ask \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $AGENT_API_KEY" \
  -H "X-User-Id: sv-test" \
  -d '{"question":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/ask \
    -H "Content-Type: application/json" \
    -H "X-API-Key: $AGENT_API_KEY" \
    -H "X-User-Id: sv-test" \
    -d '{"question":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Output thật khi chạy các lệnh trên vào bản deploy (2026-09-28):

```
$ curl -i <URL>/health
HTTP/1.1 200 OK
{"status":"ok","service":"day12-agent","version":"1.0.0"}

$ curl -i <URL>/ready
HTTP/1.1 200 OK
{"status":"ready","redis":true}

$ curl -i -X POST <URL>/ask   (không có API key)
HTTP/1.1 401 Unauthorized
{"detail":"invalid or missing API key"}

$ for i in $(seq 1 15); do curl ... /ask; done   # rate limit, user sv-test
200 200 200 200 200 200 200 200 200 200 429 429 429 429 429

$ curl -i -X POST <URL>/ask -H "X-API-Key: $AGENT_API_KEY" -H "X-User-Id: sv-test"   (body gửi từ file UTF-8, sau khi hết cửa sổ rate limit 60s)
HTTP/1.1 200 OK
{"answer":"Câu hỏi hay. Deploy là gì thường được giải quyết bằng cách chuẩn hóa môi trường chạy: cùng một image chạy giống nhau ở laptop và trên cloud. (Mình đang nhớ 20 lượt trao đổi trước đó.)","user_id":"sv-test","history_length":20,"cost_usd":9.285e-05,"tokens":{"in":439,"out":45}}
```

Ghi chú: lần đầu chạy lệnh 4 bằng Git Bash trên Windows, chuỗi tiếng Việt trong
`-d '...'` bị đổi encoding nên server trả `400 {"detail":"There was an error parsing the body"}`
(API key đã được chấp nhận). Gửi cùng câu hỏi bằng `--data-binary @body.json`
(file UTF-8) thì trả 200 như trên. `history_length: 20` cho thấy lịch sử được cắt
còn 20 message gần nhất trong Redis trên cloud.

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/health.png` — kết quả gọi `/health` từ trình duyệt hoặc curl
