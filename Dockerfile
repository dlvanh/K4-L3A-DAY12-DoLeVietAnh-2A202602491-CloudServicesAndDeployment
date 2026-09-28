# ═══════════════════════════════════════════════════════════════════
# CP2 — Production Dockerfile (multi-stage)
#
# Stage 1 `builder`: cài dependency vào /install (có thể cần compiler).
# Stage 2 `runtime`: chỉ copy kết quả đã cài + source code, chạy bằng user
#                    thường, có HEALTHCHECK, đọc cổng từ $PORT.
#
# Kiểm tra:  pytest tests/test_cp2.py -v
# Build thử: docker build -t day12-agent:prod .
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ───────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Chỉ copy requirements trước → sửa code không làm mất cache layer pip install
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ───────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

# Thư viện đã cài ở stage builder, không mang theo pip cache hay build tool
COPY --from=builder /install /usr/local

# User thường, không có quyền root
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

# Source code copy SAU cùng — layer thay đổi thường xuyên nhất
COPY --chown=appuser:appuser utils ./utils
COPY --chown=appuser:appuser app ./app

USER appuser

EXPOSE 8000

# Slim image không có curl → dùng Python để gọi /health
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('PORT', '8000') + '/health', timeout=4).read()" || exit 1

# sh -c để shell nội suy ${PORT}; exec để uvicorn là PID 1 và nhận SIGTERM trực tiếp
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
