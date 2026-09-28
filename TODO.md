# TODO — K4 L3A Day 12: Cloud Services & Deployment

Tick `[x]` as you go. Details for each item: [CLAUDE.md](CLAUDE.md) and [LAB_GUIDE.md](LAB_GUIDE.md).
Commit at the end of every checkpoint.

| Checkpoint | Points | Check command | Status |
|---|---:|---|---|
| CP0 — Setup | — | `pytest tests/ -v -m "not docker"` runs | ✅ |
| CP1 — Config, Health & Logging | 15 | `pytest tests/test_cp1.py -v` | ✅ 13/13 |
| CP2 — Docker | 15 | `pytest tests/test_cp2.py -v` | ✅ 16/16 |
| CP3 — API Security | 20 | `pytest tests/test_cp3.py -v` | ✅ 22/22 |
| CP4 — Scaling & Reliability | 20 | `pytest tests/test_cp4.py -v` | ✅ 19/19 |
| CP5 — Cloud Deployment | 15 | `pytest tests/test_cp5.py -v` | ✅ 9/9 (Railway) |
| exercises.md | 15 | `python grade.py` | ⬜ |
| Bonus — CI/CD | +10 | `pytest tests/test_bonus_cicd.py -v` | ⬜ |

---

## CP0 — Setup

- [x] Create venv and activate it (`python -m venv .venv; .venv\Scripts\Activate.ps1`)
- [x] `pip install -r requirements.txt`
- [x] `copy .env.example .env`
- [x] Generate a key and set `AGENT_API_KEY` in `.env`
- [x] Start Redis: `docker compose up -d redis` (or set `REDIS_URL=fake://`)
- [x] `pytest tests/ -v -m "not docker"` runs without `ModuleNotFoundError`
- [x] Commit: "Checkpoint 0"

## CP1 — 12-Factor Config, Health & Logging (15)

**`app/config.py`**
- [x] Declare `port: int = 8000`
- [x] Declare `agent_api_key: str` (no default → fail fast)
- [x] Declare `redis_url: str = "redis://localhost:6379/0"`
- [x] Declare `rate_limit_per_minute: int = 10`
- [x] Declare `monthly_budget_usd: float = 10.0`
- [x] Declare `log_level: str = "INFO"`

**`app/logging_utils.py`**
- [x] `log_event` builds a dict with `event`, lowercase `level`, `timestamp` + `**fields`
- [x] Prints one-line JSON (`ensure_ascii=False`, no `indent`) and returns it

**`app/main.py` — `/health`**
- [x] No parameters in `health()`
- [x] `lifecycle.shutting_down` → 503 `{"status": "shutting_down"}`
- [x] Otherwise 200 `{"status": "ok", "service", "version"}`

**Verify**
- [x] `uvicorn app.main:app --reload --port 8000` + `curl.exe -i http://localhost:8000/health`
- [x] `pytest tests/test_cp1.py -v` all green
- [x] Commit: "Checkpoint 1"

## CP2 — Docker (15)

**Before editing**
- [x] Record the single-stage image size (for exercise Q3): **1.73 GB** single-stage vs **271 MB** multi-stage
      `git show 1bf8ea5:Dockerfile | docker build -f - -t agent:single .`

**`Dockerfile`**
- [x] Multi-stage: `FROM python:3.11-slim AS builder` + a runtime stage
- [x] Slim base image for both stages
- [x] `COPY requirements.txt .` before `pip install --no-cache-dir --prefix=/install ...`
- [x] Runtime: `COPY --from=builder /install /usr/local`
- [x] Copy source (`app`, `utils`) after installing dependencies
- [x] Create non-root user and switch with `USER appuser`
- [x] `HEALTHCHECK` calling `/health` (via python `urllib`, no curl in slim)
- [x] `CMD` binds `0.0.0.0` and reads `${PORT:-8000}`
- [x] No secrets / `AGENT_API_KEY=` / `password` in the file

**`.dockerignore`**
- [x] Add `.env`, `__pycache__`, `.git`, `.venv` (plus e.g. `tests`, `screenshots`, `*.md`)
- [x] Do NOT ignore `app`, `utils`, `requirements.txt`

**`docker-compose.yml` — service `agent`**
- [x] `build: .`
- [x] `ports: "8000:8000"`
- [x] `AGENT_API_KEY: ${AGENT_API_KEY}` (interpolated, not hardcoded)
- [x] `REDIS_URL: redis://redis:6379/0`
- [x] `depends_on: redis`
- [x] `healthcheck` calling `/health`

**Verify**
- [x] `docker build -t day12-agent:prod .` succeeds; `docker images day12-agent:prod` < 500 MB (note size for Q3) — **271 MB**
- [x] `docker compose up -d` → `curl.exe http://localhost:8000/health` returns 200 (verified after CP4)
- [x] `pytest tests/test_cp2.py -v` all green (including real build tests)
- [x] Commit: "Checkpoint 2"

## CP3 — API Security (20)

**`app/auth.py`**
- [x] Compare key with `secrets.compare_digest`
- [x] Missing/wrong key → 401 `"invalid or missing API key"`
- [x] Return `x_user_id` or `ANONYMOUS_USER`

**`app/rate_limiter.py`**
- [x] `hit_count`: honour `now`, `zremrangebyscore(key, 0, now - 60)`, return `zcard`
- [x] `check`: count first; `>= limit` → 429 with `Retry-After: 60`
- [x] Then `zadd` a unique member (`f"{now}:{uuid4().hex}"`) and `expire(key, 60)`

**`app/cost_guard.py`**
- [x] `spent`: `None` → `0.0`, otherwise `float(...)`
- [x] `check`: `spent + estimated_cost > budget` → 402 `"monthly budget exceeded"`
- [x] `record`: `incrbyfloat` + `expire(KEY_TTL_SECONDS)`, return `float(total)`

**`app/main.py` — `/ask`** (in this exact order)
- [x] `limiter.check(user_id)`
- [x] `guard.check(user_id)`
- [x] `history = store.get_history(user_id)`
- [x] `result = ask_llm(payload.question, history)`
- [x] `store.append` user question + assistant answer
- [x] `guard.record(user_id, result["cost_usd"])`
- [x] `log_event("ask_completed", ...)`
- [x] Return `answer`, `user_id`, `history_length`, `cost_usd`, `tokens{in,out}`

**Verify**
- [x] curl without key → 401; with key → 200; 15 calls → last ones 429
- [x] `pytest tests/test_cp3.py -v` all green
- [x] Commit: "Checkpoint 3"

## CP4 — Scaling & Reliability (20)

**`app/store.py`**
- [x] `ping`: `client.ping()` in try/except → `True`/`False`
- [x] `append`: `rpush` JSON, `ltrim(key, -HISTORY_MAX_MESSAGES, -1)`, `expire(HISTORY_TTL_SECONDS)`
- [x] `get_history`: `lrange(key, 0, -1)` + `json.loads` each (empty → `[]`)
- [x] No global dict/list holding state in `main.py` / `store.py`

**`app/main.py` — `/ready`**
- [x] Shutting down → 503 `{"status": "shutting_down"}`
- [x] `not store.ping()` → 503 `{"status": "not ready", "redis": False}`
- [x] Otherwise 200 `{"status": "ready", "redis": True}`

**`app/lifecycle.py`**
- [x] `install`: save `signal.getsignal(sig)` then `signal.signal(sig, self.request_shutdown)` for SIGTERM + SIGINT
- [x] `request_shutdown`: set `shutting_down = True`, call previous handler if `callable`

**Verify**
- [x] `pytest tests/test_cp4.py -v` all green
- [x] (Optional) scale to 3 agents behind nginx; `history_length` keeps increasing (note for Q9)
- [x] No `NotImplementedError` left: `grep -rn NotImplementedError app/`
- [x] Commit: "Checkpoint 4"

## CP5 — Cloud Deployment (15)

**Deploy (Railway or Render)**
- [x] Create platform account
- [x] Create Redis instance and attach `REDIS_URL` to the agent service
- [x] Set `AGENT_API_KEY`, `RATE_LIMIT_PER_MINUTE`, `MONTHLY_BUDGET_USD`, `LOG_LEVEL` in the dashboard (don't set `PORT`)
- [x] Deploy from Dockerfile and generate a public HTTPS domain → https://agent-production-218e.up.railway.app
- [x] `/health` → 200, `/ready` → 200, `/ask` without key → 401, with key → 200, rate limit → 429

**`DEPLOYMENT.md`**
- [x] Student info (name, mã học viên, repo link)
- [x] Real Public URL, platform, deploy date
- [x] Env var table: names + source only, no values
- [x] Paste real command output (key not expanded)
- [x] Remove every `(điền ...)` placeholder, including the fallback section if unused

**Evidence**
- [ ] `screenshots/dashboard.png`
- [ ] `screenshots/health.png`
- [x] (Optional) `DEPLOY_API_KEY=...` in local `.env` for the authenticated test

**Verify**
- [x] `pytest tests/test_cp5.py -v` all green
- [x] Commit: "Checkpoint 5"

_Fallback only if cloud is impossible:_ `LOCAL_FALLBACK=true` in `.env`, `docker compose up -d`, screenshots, write reason in DEPLOYMENT.md (CP5 capped at 9/15).

## exercises.md (15) — answer in your own words

- [ ] Fill name + mã học viên at the top
- [ ] Q1 — Fail fast
- [ ] Q2 — Machine-readable logs (paste a real JSON log line)
- [ ] Q3 — Image size (real single vs multi-stage numbers)
- [ ] Q4 — Dockerfile layer order / cache
- [ ] Q5 — Why not run as root
- [ ] Q6 — Sliding window vs fixed minute
- [ ] Q7 — Rate limit vs cost guard
- [ ] Q8 — `/health` vs `/ready`
- [ ] Q9 — Stateless (`history_length` observation)
- [ ] Q10 — A real deploy error and how you fixed it

## Bonus — CI/CD with GitHub Actions (+10)

- [ ] Create `.github/workflows/ci.yml`
- [ ] Trigger on `push` and `pull_request` to `main`
- [ ] `test` job: checkout → setup-python → `pip install -r requirements.txt` → `pytest ... --ignore=tests/test_cp5.py --ignore=tests/test_bonus_cicd.py`
- [ ] `build` job: `docker build`
- [ ] `deploy` job with `needs: [test, build]` and `if:` main + push only
- [ ] Deploy token in GitHub Secrets, referenced as `${{ secrets.* }}`
- [ ] All actions pinned (`@v4`, not `@main`)
- [ ] Smoke test `curl -fsS` on `/health` after deploy
- [ ] CI badge at the top of README.md
- [ ] Workflow green on GitHub; `pytest tests/test_bonus_cicd.py -v` all green

## Final submission

- [ ] `python grade.py` ≥ 75 (target 90+); every remaining failure understood
- [ ] `.env` not tracked: `git ls-files | grep -E '(^|/)\.env$|\.(pem|key)$'` returns nothing
- [ ] No secret values in DEPLOYMENT.md, workflow, compose, or code
- [ ] Commits spread across checkpoints
- [ ] Repo is public; push final commit
- [ ] Submit repo link on Codelab
