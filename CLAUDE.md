# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this repo is

Individual lab assignment **K4 · Level 3A · Day 12 — Cloud Services & Deployment**
(student: Đỗ Lê Việt Anh, MSSV `2A202602491`). The task is to take a small
FastAPI "AI agent" (backed by an offline mock LLM) and make it production-ready:
12-factor config, Docker, API security, stateless scaling, graceful shutdown,
and a real public cloud deployment. All docs are in Vietnamese.

- Remote: `https://github.com/dlvanh/K4-L3A-DAY12-DoLeVietAnh-2A202602491-CloudServicesAndDeployment`
  (name already matches the required `K4-L3A-DAY12-<HoVaTen>-<MSSV>-CloudServicesAndDeployment` pattern — do not rename).
- Grading: `python grade.py` → 100 pts required + up to 10 bonus (final total capped at 100).
- Authoritative docs: [README.md](README.md), [LAB_GUIDE.md](LAB_GUIDE.md) (step-by-step),
  [CHECKPOINTS.md](CHECKPOINTS.md), [RUBRIC.md](RUBRIC.md), [RULES.md](RULES.md), [SUBMISSION.md](SUBMISSION.md).
  The tests in `tests/` are the real spec — when a doc and a test disagree, the test wins.

## Academic-integrity rules Claude must follow

From [RULES.md](RULES.md). Breaking these can zero the student's grade.

- **The student must be able to explain every line.** The Lab Coach quizzes students on their code; unexplained parts get zeroed. When writing code, explain *why* (the docstrings in `app/` contain the reasoning — reuse it), keep implementations minimal and idiomatic, and don't add cleverness the student can't defend.
- **Never fabricate** test output, deploy URLs, screenshots, image sizes, log lines, or other observations. Only record what was actually run.
- **Do not write `exercises.md` answers.** They must be the student's own words based on real observations. Claude may run the commands that produce the observations (e.g. `docker images`, log output) and explain concepts, but the prose is the student's.
- **Never commit secrets**: `.env`, real `AGENT_API_KEY` values, platform tokens, `*.pem`/`*.key`. `-10` pts if leaked. `DEPLOYMENT.md` lists variable *names* only. If a secret is leaked, it must be rotated — a follow-up commit does not remove it from history.
- **After every checkpoint passes its tests, commit and push to `main`.** The commit message has a short title (e.g. `Checkpoint 1: ...`) and a body of 1–2 sentences summarizing what the checkpoint accomplished. One commit per checkpoint is also what the graders expect; a single last-minute commit looks suspicious. Never stage `.env`.
- Tick completed items in [TODO.md](TODO.md) as part of each checkpoint commit.
- The real server can't start until CP4's `lifecycle.install()` is implemented, because `lifespan` calls it. Before then, smoke-test with that hook stubbed out.

## Environment notes (this machine)

- Windows 11, PowerShell 5.1 primary; Git Bash also available. Local Python is 3.14 (lab requires ≥3.11); Docker 29 is installed.
- In PowerShell, `curl` is an alias for `Invoke-WebRequest` — use `curl.exe`, or run the lab's bash snippets (`for i in $(seq 1 15)...`) in Git Bash.
- Setup:
  ```powershell
  python -m venv .venv; .venv\Scripts\Activate.ps1; pip install -r requirements.txt
  copy .env.example .env      # then set AGENT_API_KEY to: python -c "import secrets; print(secrets.token_urlsafe(32))"
  docker compose up -d redis  # or REDIS_URL=fake:// in .env if Docker is unavailable
  ```
- Run everything from the repo root (otherwise `ModuleNotFoundError: app`).

## Commands

```bash
pytest tests/test_cp1.py -v              # one checkpoint
pytest tests/ -v -m "not docker"         # everything except the slow real image build
pytest tests/test_cp3.py -x --tb=short   # stop at first failure
python grade.py --no-bonus               # score required parts only (no network for badge)
python grade.py                          # full score incl. bonus
uvicorn app.main:app --reload --port 8000
```

`tests/conftest.py` forces `AGENT_API_KEY=test-api-key-cua-lab` and `REDIS_URL=fake://`,
and overrides the Redis-backed dependencies with `fakeredis`, so tests never need a
real Redis or the student's `.env` (except CP5, which reads `LOCAL_FALLBACK` / `DEPLOY_API_KEY` from `.env`).
CP1/CP3 tests use a `StubStore`, so CP3 can pass before CP4 is done.

## Architecture

```
POST /ask ─► verify_api_key (401) ─► RateLimiter.check (429) ─► CostGuard.check (402)
          ─► store.get_history ─► ask_llm (mock) ─► store.append ×2 ─► guard.record ─► log_event
GET /health  liveness: no dependencies; 503 while shutting down
GET /ready   readiness: pings Redis via store; 503 if Redis down or shutting down
```

| File | CP | What to implement (every `raise NotImplementedError` must go) |
|---|---|---|
| `app/config.py` | 1 | 6 `Settings` fields; `agent_api_key: str` has **no default** (fail fast) |
| `app/logging_utils.py` | 1 | `log_event`: one-line JSON (`event`, lowercase `level`, `timestamp`, + `**fields`), `ensure_ascii=False`, print + return |
| `app/main.py` | 1/3/4 | `/health`, `/ready`, `/ask` exactly in the order in its docstring |
| `app/auth.py` | 3 | `verify_api_key` with `secrets.compare_digest`; returns `X-User-Id` or `"anonymous"` |
| `app/rate_limiter.py` | 3 | Sliding window on a Redis ZSET |
| `app/cost_guard.py` | 3 | `spent` / `check` (402) / `record` (`incrbyfloat` + `expire`) |
| `app/store.py` | 4 | `ping` (swallow all exceptions → `False`), `append` (`rpush`+`ltrim`+`expire`), `get_history` |
| `app/lifecycle.py` | 4 | `install` (remember old handlers, then register) and `request_shutdown` (set flag, chain to old handler) |
| `Dockerfile`, `.dockerignore`, `docker-compose.yml` | 2 | See CP2 below |
| `DEPLOYMENT.md`, `screenshots/` | 5 | Real URL + evidence |
| `exercises.md` | — | 10 answers, written by the student |
| `.github/workflows/ci.yml`, README badge | bonus | See Bonus below |

Given files — don't modify: `utils/mock_llm.py`, `tests/`, `grade.py`, `nginx/nginx.conf`. The helper methods marked `CHO SẴN` ("provided") in `app/` are also fixed.

## Completion plan, checkpoint by checkpoint

Each file's docstrings give exact step-by-step instructions (in Vietnamese). Follow them literally; the notes below cover the traps the tests check for.

### CP0 — Setup
Venv, `pip install`, `.env`, Redis. `pytest tests/ -v -m "not docker"` should *run* (most tests failing is expected at this stage).

### CP1 — Config, health, logging (15 pts) — `tests/test_cp1.py`
- `Settings` defaults: `port=8000`, `redis_url="redis://localhost:6379/0"`, `rate_limit_per_minute=10`, `monthly_budget_usd=10.0`, `log_level="INFO"`.
- `health()` must take **no parameters** (test inspects its signature). Check `lifecycle.shutting_down` → `JSONResponse(503, {"status": "shutting_down"})`, else `{"status": "ok", "service": SERVICE_NAME, "version": SERVICE_VERSION}`.
- Forbidden substrings in `config.py`, `main.py`, `auth.py`: `sk-`, `AKIA`, `password123`, `secret-key-123`. Watch for innocent words like `task-`/`risk-`/`disk-`, which contain `sk-`.

### CP2 — Docker (15 pts) — `tests/test_cp2.py`
The tests read the Dockerfile with `#` comment lines stripped, then check:
- ≥2 `FROM`, at least one named (`FROM python:3.11-slim AS builder`); a `slim`/`alpine` base.
- The literal text `COPY requirements.txt` appears **before** the first `pip install` (so don't put a `pip install --upgrade pip` above it), and any `COPY . .` comes after `pip install`. Prefer `COPY app ./app` + `COPY utils ./utils`.
- Builder: `pip install --no-cache-dir --prefix=/install -r requirements.txt`; runtime: `COPY --from=builder /install /usr/local`.
- A non-root user (`useradd --uid 10001 appuser` + final `USER appuser`), and a `HEALTHCHECK`. The slim image has no curl, so use `python -c "import urllib.request; ..."`.
- `CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]`.
- No `sk-`, `AGENT_API_KEY=`, or `password` anywhere in non-comment lines.
- Image < 500 MB (the real-build test is marked `docker` and is skipped if the daemon is off).
- `.dockerignore` must contain `.env`, `__pycache__`, `.git`, `.venv`, and must **not** contain a bare `app`, `app/`, `utils`, or `requirements.txt` line.
- `docker-compose.yml` `agent` service: `build: .`, `ports: ["8000:8000"]`, `depends_on: [redis]`, a `healthcheck`, and
  `environment: {AGENT_API_KEY: "${AGENT_API_KEY}", REDIS_URL: "redis://redis:6379/0"}` (the value must start with `${`; the Redis host is the service name, not localhost).
- `docker compose up --scale agent=3` conflicts with a fixed `8000:8000` host port. For the optional scaling demo, put the `nginx` service in front, or use a port range.
- **Before editing the Dockerfile**, note that exercise 3 needs the original single-stage size. It stays retrievable from git: `git show 1bf8ea5:Dockerfile | docker build -f - -t agent:single .`

### CP3 — API security (20 pts) — `tests/test_cp3.py`
- `auth.py`: must actually *call* `secrets.compare_digest` (checked via AST). Missing or wrong key → 401 `"invalid or missing API key"`.
- `rate_limiter.py`: honour the `now` argument (tests pass fake timestamps; don't call `time.time()` unconditionally). Order: `zremrangebyscore(key, 0, now-60)` → `zcard` → if `>= limit` raise 429 with `Retry-After` → **then** `zadd` a unique member `f"{now}:{uuid4().hex}"` → `expire`. Adding before counting blocks one request too early.
- `cost_guard.py`: `spent` returns `0.0` when the key is missing (Redis returns `None`) and casts to `float`. `check` raises 402 when `spent + estimated > budget`.
- `/ask`: `limiter.check` → `guard.check` → history → `ask_llm` → append user + assistant → `guard.record` → `log_event("ask_completed", ...)` → return `answer, user_id, history_length=len(history), cost_usd, tokens{in,out}`. Checks must happen before the LLM call.

### CP4 — Scaling & reliability (20 pts) — `tests/test_cp4.py`
- `store.append`: `ltrim(key, -HISTORY_MAX_MESSAGES, -1)`, which keeps the newest messages (`0, N-1` would keep the oldest and fail).
- No module-level `dict`/`list` whose name contains history/conversation/session/cache/memory/store in `main.py` or `store.py` (regex-checked).
- `/ready`: shutting down → 503 `{"status": "shutting_down"}`; `not store.ping()` → 503 `{"status": "not ready", "redis": False}`; else `{"status": "ready", "redis": True}`.
- `lifecycle.install`: pass `self.request_shutdown` (a reference, not a call). `request_shutdown` must call the previous handler only if `callable(previous)`, because `SIG_DFL`/`SIG_IGN` aren't callable. Chaining matters because uvicorn's own handler is what actually stops the server.

### CP5 — Cloud deployment (15 pts) — `tests/test_cp5.py`
1. Deploy with **Railway** (`railway init` → `railway add --database redis` → `railway variables --set AGENT_API_KEY=... ...` → `railway up` → `railway domain`; make sure `REDIS_URL` is attached to the agent service; don't override `PORT`) **or Render** (New → Blueprint using `render.yaml`; enter `AGENT_API_KEY` when prompted). Deploying and creating accounts are outward-facing actions the student runs or approves explicitly.
2. Verify with `curl.exe -i <URL>/health`, `/ready`, and `POST /ask` without a key (expect 401). If `/ready` returns 503, `REDIS_URL` is wrong.
3. Fill in [DEPLOYMENT.md](DEPLOYMENT.md). The test fails if **any** `(điền` placeholder remains, including the fallback-section placeholder at the bottom: delete that section when not using the fallback. Other requirements:
   - It must still contain the text "Mã học viên" and name the platform.
   - It must list `AGENT_API_KEY` and `REDIS_URL` by name. `AGENT_API_KEY=<12+ chars>` or `AGENT_API_KEY: <value>` anywhere in the file fails.
   - The test uses the first `https://` URL that isn't github.com, a placeholder, or a Railway dashboard link. It must be the live service, over HTTPS.
   - Paste real command output only, and never with the key expanded.
4. Screenshots: `screenshots/dashboard.png`, `screenshots/health.png`. The student takes these; Claude can't.
5. Optional extra test: put `DEPLOY_API_KEY=<the key set on the platform>` in the local `.env` (never committed).
6. If cloud deployment is impossible: set `LOCAL_FALLBACK=true` in `.env`, run `docker compose up -d`, take screenshots, and write the reason in DEPLOYMENT.md. CP5 is then capped at 9/15.

### exercises.md (15 pts)
`grade.py` counts how many of the 10 `> *Câu trả lời của bạn*` placeholders were replaced; quality is graded by hand. The student writes the answers. Claude can help collect the real data they reference: image sizes for Q3, a JSON log line for Q2, cache behaviour for Q4, `history_length` across scaled containers for Q9, and a real deploy error for Q10.

### Bonus — CI/CD (+10) — `tests/test_bonus_cicd.py`
Create `.github/workflows/ci.yml` (the lab provides no template):
- `on: push` and `pull_request` on `main`.
- A `test` job: `actions/checkout@v4` → `actions/setup-python@v5` → `pip install -r requirements.txt` → `pytest tests/ -v --ignore=tests/test_cp5.py --ignore=tests/test_bonus_cicd.py`. The pytest line must contain `ignore`, `-k`, `-m`, or `test_cp5`.
- A `build` job: `docker build -t day12-agent:ci .`
- A job named `deploy` with `needs: [test, build]` and `if: github.ref == 'refs/heads/main' && github.event_name == 'push'`. It deploys using `${{ secrets.RAILWAY_TOKEN }}` (or a Render deploy-hook secret) and ends with a smoke test: `curl -fsS "${{ vars.PUBLIC_URL }}/health"`.
- Pin every action to a version tag (no `@main`/`@master`/`@latest`).
- No literal value of 16+ characters after a `TOKEN|KEY|SECRET|PASSWORD:` key. Even a dummy like `AGENT_API_KEY: ci-dummy-key-for-tests` trips the check, so keep dummies short (`ci-dummy`).
- Add to the top of README.md:
  `![CI](https://github.com/dlvanh/K4-L3A-DAY12-DoLeVietAnh-2A202602491-CloudServicesAndDeployment/actions/workflows/ci.yml/badge.svg)`.
  The last test downloads it and requires `passing`, so the repo must be public and the workflow must go green on GitHub.

## Pre-submission checklist

- `grep -rn NotImplementedError app/` returns nothing.
- `python grade.py` scores ≥ 75 (target 90+), and every remaining failure is understood.
- `git ls-files | grep -E '(^|/)\.env$|\.(pem|key)$'` returns nothing (only `.env.example` is tracked).
- DEPLOYMENT.md has no placeholders or secret values; screenshots are present; `exercises.md` has all 10 answers.
- The repo is public; commits are spread across checkpoints; submit the repo link on Codelab.
