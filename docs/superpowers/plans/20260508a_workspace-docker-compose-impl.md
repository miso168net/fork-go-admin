# Workspace Docker Compose Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Materialize the workspace-level `docker-compose.yml` + supporting files (go.work, two settings yamls, sqlite seed, entrypoint shell) so a developer can run `docker compose --profile {mysql,sqlite} up` against the seven `fork260506-*` sub-repos without modifying any of them.

**Architecture:** Bind-mount all 7 sub-repos into containers; backend uses a workspace-level `go.work` to resolve the four lib repos as local modules; settings/db files live in `<workspace>/config/`; one yaml file with two profiles selects mysql vs sqlite.

**Tech Stack:** Docker Compose v2 (profiles), Go 1.24 + go.work, Node 18 (vue-cli serve), MySQL 8.0, SQLite3 (CGO).

**Spec:** `docs/superpowers/specs/20260508a_workspace-docker-compose-design.md` (commit `4b8e720`).

---

## File Structure

| Path | Owner | Purpose |
|---|---|---|
| `<workspace>/docker-compose.yml` | Created in T7 | Hybrid-profile compose (mysql / sqlite) — single source of truth for service topology |
| `<workspace>/go.work` | Created in T3 | Go workspace listing 5 Go module repos as `use` directives |
| `<workspace>/config/settings.workspace-mysql.yml` | Created in T4 | mysql DSN + workspace overrides;bind-mounted to backend `/config/settings.yml` |
| `<workspace>/config/settings.workspace-sqlite.yml` | Created in T5 | sqlite DSN + workspace overrides;same mount target,sqlite profile only |
| `<workspace>/config/go-admin-db.db` | Copied in T2 | sqlite seed (348 KB);bind-mounted rw to backend `/go-admin-db.db` |
| `<workspace>/scripts/backend-entrypoint.sh` | Created in T6 | apk-install CGO toolchain + go.sum tidy fallback + `exec go run -tags sqlite3` |

All edits stay at `<workspace>` root. **No file inside any `fork260506-*/` is modified or staged.**

---

## Task 1: Bootstrap workspace directories

**Files:**
- Create: `<workspace>/config/` (directory)
- Create: `<workspace>/scripts/` (directory)

- [ ] **Step 1: Verify current state**

```bash
cd /mnt/d/AnewSpaces/Local/x_Project/TEST-claude/fork-go-admin
ls -la config scripts 2>&1 | head -5
```

Expected: `ls: cannot access 'config': No such file or directory`(directories not yet created)

- [ ] **Step 2: Create the two directories**

```bash
mkdir -p config scripts
ls -ld config scripts
```

Expected: two `drwxr...` lines for `config` and `scripts`

- [ ] **Step 3: Verify workspace tree shape**

```bash
ls -1 config scripts
```

Expected: both directories exist and are empty

- [ ] **Step 4: Commit (deferred — empty dirs are not tracked by git; first commit lands in T2)**

No commit yet. Empty directories are not stored in git;they will be implicitly committed when their first file lands.

---

## Task 2: Copy sqlite seed database

**Files:**
- Source: `<workspace>/fork260506-go-admin/go-admin-db.db` (348160 bytes,already on disk)
- Create: `<workspace>/config/go-admin-db.db`

- [ ] **Step 1: Verify source exists with expected size**

```bash
stat -c '%n %s' fork260506-go-admin/go-admin-db.db
```

Expected: `fork260506-go-admin/go-admin-db.db 348160`

- [ ] **Step 2: Copy seed to workspace config**

```bash
cp fork260506-go-admin/go-admin-db.db config/go-admin-db.db
```

Expected: no output(silent success)

- [ ] **Step 3: Verify destination matches source byte-for-byte**

```bash
cmp fork260506-go-admin/go-admin-db.db config/go-admin-db.db && echo "identical"
```

Expected: `identical`

- [ ] **Step 4: Commit**

```bash
git add config/go-admin-db.db
git commit -m "$(cat <<'EOF'
chore(workspace): copy sqlite seed db to config/

Per spec §2.1: workspace owns its sqlite seed so future schema
changes can be made without touching fork260506-go-admin.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

Expected: `[main <hash>] chore(workspace): copy sqlite seed db to config/`,1 file changed,348 KB binary added

---

## Task 3: Create `go.work`

**Files:**
- Create: `<workspace>/go.work`

- [ ] **Step 1: Write `go.work` with 5 use directives**

```bash
cat > go.work <<'EOF'
go 1.24

use (
    ./fork260506-go-admin
    ./fork260506-go-admin-core
    ./fork260506-gorm-adapter
    ./fork260506-redis-watcher
    ./fork260506-redisqueue
)
EOF
```

- [ ] **Step 2: Verify content**

```bash
cat go.work
```

Expected: exact content above (no trailing whitespace, 5 use lines)

- [ ] **Step 3: (Optional) Verify go.work is parseable**

If Go 1.24 is on host:
```bash
GOWORK=$(pwd)/go.work go env GOWORK
```
Expected: `<workspace>/go.work`

If Go is not on host: skip this step — the same check inside the backend container is the authoritative one (verified in T8).

- [ ] **Step 4: Commit**

```bash
git add go.work
git commit -m "$(cat <<'EOF'
chore(workspace): add go.work for cross-module local resolution

Lists the 5 Go module sub-repos as use directives so backend
imports of go-admin-core / gorm-adapter / redis-watcher / redisqueue
resolve to the bind-mounted local copies (no go.mod replace needed).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create `config/settings.workspace-mysql.yml`

**Files:**
- Create: `<workspace>/config/settings.workspace-mysql.yml`

- [ ] **Step 1: Write the file (verbatim from spec §2.5)**

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# 來源:fork260506-go-admin/config/settings.yml (main, mysql template) 為基底
# 修改:DSN 從 host=127.0.0.1 → mysql (compose service DNS)
#       帳密 user:password/dbname → go-admin:go-admin123/go-admin
#       timeout 1000ms → 10000ms (避開 mysql 首啟 race;learning-docs §6.2)
#       charset utf8 → utf8mb4 (對齊 mysql 8 server,相容 emoji)
# Generated by: docs/superpowers/specs/20260508a_workspace-docker-compose-design.md
# ─────────────────────────────────────────────────────────────────────────────
settings:
  application:
    mode: dev                     # from: settings.yml:4
    host: 0.0.0.0                 # from: settings.yml:6  (本來就 0.0.0.0,容器化也適用)
    name: testApp                 # from: settings.yml:8
    port: 8000                    # from: settings.yml:10
    readtimeout: 3000             # from: settings.sqlite.yml:11 (settings.yml 是 1,太短)
    writertimeout: 2000           # from: settings.sqlite.yml:12 (settings.yml 是 2,太短)
    enabledp: false               # from: settings.yml:14
  logger:
    path: temp/logs               # from: settings.yml:17
    stdout: ''                    # from: settings.yml:19
    level: trace                  # from: settings.yml:21
    enableddb: false              # from: settings.yml:23
  jwt:
    secret: go-admin              # from: settings.yml:26 (生產要改)
    timeout: 3600                 # from: settings.yml:28
  database:
    driver: mysql                 # from: settings.yml:32
    # ▼ 修改:127.0.0.1 → mysql (compose service name,bridge net 內部 DNS)
    # ▼ 修改:user:password/dbname → go-admin:go-admin123/go-admin (對齊 docker-compose env)
    # ▼ 修改:utf8 → utf8mb4 (對齊 mysql 8 + emoji)
    # ▼ 修改:timeout=1000ms → 10000ms (learning-docs §6.2 故障排除建議)
    source: go-admin:go-admin123@tcp(mysql:3306)/go-admin?charset=utf8mb4&parseTime=True&loc=Local&timeout=10000ms
  gen:
    dbname: go-admin              # from: settings.yml:45 (改為實際 db 名)
    frontpath: ../go-admin-ui/src # from: settings.yml:47
  extend:                         # from: settings.yml:48
    demo:
      name: data
  cache:
    memory: ''                    # from: settings.yml:57
  queue:
    memory:
      poolSize: 100               # from: settings.yml:60
```

Use the Write tool with the absolute path `/mnt/d/AnewSpaces/Local/x_Project/TEST-claude/fork-go-admin/config/settings.workspace-mysql.yml` and the content above.

- [ ] **Step 2: Verify yaml is parseable**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('config/settings.workspace-mysql.yml')); print('yaml OK')"
```

Expected: `yaml OK`

(If python3 is not present, fall back to: `docker run --rm -v "$(pwd)/config:/c" mikefarah/yq:latest 'eval' /c/settings.workspace-mysql.yml > /dev/null && echo "yaml OK"`)

- [ ] **Step 3: Spot-check key fields**

```bash
grep -E '^\s*(driver|source):' config/settings.workspace-mysql.yml
```

Expected:
```
    driver: mysql
    source: go-admin:go-admin123@tcp(mysql:3306)/go-admin?charset=utf8mb4&parseTime=True&loc=Local&timeout=10000ms
```

- [ ] **Step 4: Commit**

```bash
git add config/settings.workspace-mysql.yml
git commit -m "$(cat <<'EOF'
chore(workspace): add settings.workspace-mysql.yml

Mysql DSN points at compose service `mysql:3306`, charset utf8mb4,
timeout 10s (learning-docs §6.2 first-startup race avoidance).
Source provenance annotated inline per spec §2.5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Create `config/settings.workspace-sqlite.yml`

**Files:**
- Create: `<workspace>/config/settings.workspace-sqlite.yml`

- [ ] **Step 1: Write the file (verbatim from spec §2.6)**

```yaml
# ─────────────────────────────────────────────────────────────────────────────
# 來源:fork260506-go-admin/config/settings.sqlite.yml (main,與 001 分支內容相同)
# 修改:database.source 從 `go-admin-db.db` (相對 cwd) → `/go-admin-db.db` (絕對路徑,
#       對應 docker-compose 的 bind-mount `./config/go-admin-db.db:/go-admin-db.db`)
# 注意:本 dev stack 不啟用 GORM SQL log;若要走 login-trace 學習,可手動把
#       enableddb 改 true (對齊 001 分支 Dockerfile.learning 的 sed 行為)
# Generated by: docs/superpowers/specs/20260508a_workspace-docker-compose-design.md
# ─────────────────────────────────────────────────────────────────────────────
settings:
  application:
    mode: dev                     # from: settings.sqlite.yml:4
    host: 0.0.0.0                 # from: settings.sqlite.yml:6
    name: testApp                 # from: settings.sqlite.yml:8
    port: 8000                    # from: settings.sqlite.yml:10
    readtimeout: 3000             # from: settings.sqlite.yml:11
    writertimeout: 2000           # from: settings.sqlite.yml:12
    enabledp: false               # from: settings.sqlite.yml:14
  logger:
    path: temp/logs               # from: settings.sqlite.yml:17
    stdout: ''                    # from: settings.sqlite.yml:19
    level: trace                  # from: settings.sqlite.yml:21
    enableddb: false              # from: settings.sqlite.yml:23 (走 learning-trace 改 true)
  jwt:
    secret: go-admin              # from: settings.sqlite.yml:26
    timeout: 3600                 # from: settings.sqlite.yml:28
  database:
    driver: sqlite3               # from: settings.sqlite.yml:31
    # ▼ 修改:`go-admin-db.db` → `/go-admin-db.db` (絕對路徑,對應 bind-mount)
    source: /go-admin-db.db
  gen:
    dbname: dbname                # from: settings.sqlite.yml:36
    frontpath: ../go-admin-ui/src # from: settings.sqlite.yml:38
```

Use the Write tool with the absolute path `/mnt/d/AnewSpaces/Local/x_Project/TEST-claude/fork-go-admin/config/settings.workspace-sqlite.yml`.

- [ ] **Step 2: Verify yaml is parseable**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('config/settings.workspace-sqlite.yml')); print('yaml OK')"
```

Expected: `yaml OK`

- [ ] **Step 3: Spot-check key fields**

```bash
grep -E '^\s*(driver|source):' config/settings.workspace-sqlite.yml
```

Expected:
```
    driver: sqlite3
    source: /go-admin-db.db
```

- [ ] **Step 4: Commit**

```bash
git add config/settings.workspace-sqlite.yml
git commit -m "$(cat <<'EOF'
chore(workspace): add settings.workspace-sqlite.yml

Sqlite source path set to /go-admin-db.db (absolute, matches the
bind-mount target in docker-compose). Source provenance per spec §2.6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Create `scripts/backend-entrypoint.sh`

**Files:**
- Create: `<workspace>/scripts/backend-entrypoint.sh`

- [ ] **Step 1: Write the script (verbatim from spec §2.7)**

```bash
#!/bin/sh
# Source: derived from fork260506-go-admin/Dockerfile.learning (001 分支) line 11-20
# 註:本 script 不設 GOPROXY/GOSUMDB(Taiwan 直連 proxy.golang.org / sum.golang.org)。
#    若在中國網路下,可在 docker-compose.yml 的 x-backend-base.environment 取消註解
#    GOPROXY=https://goproxy.cn,direct 與 GOSUMDB=sum.golang.google.cn。
set -e

# (1) CGO toolchain — sqlite 需 CGO,golang:1.24-alpine 沒 gcc。
#     `docker compose stop/start` 保留容器 → 不會重裝;
#     `docker compose down/up` 重建容器 → 會重裝(額外 ~30s 一次)。
command -v gcc >/dev/null 2>&1 || apk add --no-cache gcc g++ libc6-compat sqlite tzdata

cd /workspace/fork260506-go-admin

# (2) go.sum tidy fallback —
#     fork260506-go-admin/.gitignore 忽略 go.sum (參見 Dockerfile.learning:11-15 觀察),
#     bind-mount 進來時可能缺;只跑 `go mod download` 不夠 (Go 1.17+ 不會填 transitive go.sum)。
[ ! -f go.sum ] && go mod tidy

# (3) `go run` with sqlite3 build tag —
#     對應 Dockerfile.learning:20 的 `go build -tags sqlite3`;
#     mysql 變體不需要此 tag,但加上去也只是多 link 一個未用的驅動,無害。
exec go run -tags sqlite3 main.go "$@"
```

Use the Write tool with the absolute path `/mnt/d/AnewSpaces/Local/x_Project/TEST-claude/fork-go-admin/scripts/backend-entrypoint.sh`.

- [ ] **Step 2: Make it executable**

```bash
chmod +x scripts/backend-entrypoint.sh
ls -l scripts/backend-entrypoint.sh
```

Expected: file mode shows `-rwxr-xr-x` (or similar with x bits set)

- [ ] **Step 3: Verify shell syntax**

```bash
sh -n scripts/backend-entrypoint.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 4: Commit**

```bash
git add scripts/backend-entrypoint.sh
git commit -m "$(cat <<'EOF'
chore(workspace): add backend-entrypoint.sh

Installs CGO toolchain (gcc/g++/libc6-compat/sqlite) on first run,
runs `go mod tidy` if go.sum is missing (fork260506-go-admin gitignores
go.sum), and execs `go run -tags sqlite3 main.go "$@"`. Logic per spec §2.7.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Create `docker-compose.yml` and validate both profiles

**Files:**
- Create: `<workspace>/docker-compose.yml`

- [ ] **Step 1: Write the compose file (verbatim from spec §3)**

```yaml
# Workspace-level docker-compose for fork-go-admin
# Spec: docs/superpowers/specs/20260508a_workspace-docker-compose-design.md
#
# Profiles:
#   docker compose --profile mysql up -d   → 4-svc (mysql + migrate + go-admin-mysql + go-admin-ui)
#   docker compose --profile sqlite up -d  → 2-svc (go-admin-sqlite + go-admin-ui)
#
# Sources annotated inline. See spec §2.2 for full provenance matrix.

# ─── yaml anchor:backend service base ────────────────────────────────────
# 設計提醒:`<<: *backend-base` 只 merge mapping;list (volumes/command/ports)
#          每個 service 仍要重寫。把不變的 image/env/entrypoint/networks 抽到此處。
x-backend-base: &backend-base
  image: golang:1.24-alpine                      # from: Dockerfile.learning:7
  working_dir: /workspace/fork260506-go-admin    # entrypoint cd 到這裡
  environment:
    # ─── 中國網路 mirror (作者 lwnmengjing 來自中國;Taiwan 不需要,留作參考) ───
    # GOPROXY: https://goproxy.cn,direct         # from: fork260506-go-admin/Dockerfilebak:5
    # GOSUMDB: sum.golang.google.cn              # 對齊上行,中國防火牆下需要
    TZ: Asia/Shanghai                            # from: Dockerfile.learning:25
  entrypoint: ["sh", "/usr/local/bin/backend-entrypoint.sh"]
  networks: [workspace-net]

services:
  # ═══ Always-on (兩個 profile 都跑) ════════════════════════════════════════
  go-admin-ui:
    image: node:18-alpine
    container_name: go-admin-ui
    working_dir: /app
    ports: ["8080:8080"]
    volumes:
      - ./fork260506-go-admin-ui:/app
      - node-modules-go-admin-ui:/app/node_modules
    environment:
      port: "8080"
      VUE_APP_BASE_API: http://localhost:8000
      TZ: Asia/Shanghai
    command:
      - sh
      - -c
      - |
        if [ ! -d node_modules ] || [ -z "$$(ls -A node_modules 2>/dev/null)" ]; then
          # ─── 中國網路 mirror (Taiwan 不需要,留作參考) ───
          # npm config set registry https://registry.npmmirror.com
          # npm install -g cnpm --registry=https://registry.npmmirror.com
          # cnpm install
          npm install
        fi
        npm run dev
    networks: [workspace-net]

  # ═══ mysql profile ═══════════════════════════════════════════════════════
  mysql:
    image: mysql:8.0
    container_name: workspace-mysql
    profiles: [mysql]
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --innodb-default-row-format=DYNAMIC
    environment:
      MYSQL_ROOT_PASSWORD: rootpw
      MYSQL_DATABASE: go-admin
      MYSQL_USER: go-admin
      MYSQL_PASSWORD: go-admin123
      TZ: Asia/Shanghai
    volumes:
      - mysql-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "go-admin", "-pgo-admin123"]
      interval: 5s
      timeout: 3s
      retries: 30
      start_period: 30s
    networks: [workspace-net]

  migrate:
    <<: *backend-base
    container_name: workspace-migrate
    profiles: [mysql]
    restart: "no"
    command: ["migrate", "-c", "/config/settings.yml"]
    volumes:
      - ./fork260506-go-admin:/workspace/fork260506-go-admin
      - ./fork260506-go-admin-core:/workspace/fork260506-go-admin-core
      - ./fork260506-gorm-adapter:/workspace/fork260506-gorm-adapter
      - ./fork260506-redis-watcher:/workspace/fork260506-redis-watcher
      - ./fork260506-redisqueue:/workspace/fork260506-redisqueue
      - ./go.work:/workspace/go.work:ro
      - ./scripts/backend-entrypoint.sh:/usr/local/bin/backend-entrypoint.sh:ro
      - ./config/settings.workspace-mysql.yml:/config/settings.yml:ro
      - go-mod-cache:/go/pkg/mod
    depends_on:
      mysql: { condition: service_healthy }

  go-admin-mysql:
    <<: *backend-base
    container_name: go-admin-mysql
    profiles: [mysql]
    ports: ["8000:8000"]
    command: ["server", "-c", "/config/settings.yml"]
    volumes:
      - ./fork260506-go-admin:/workspace/fork260506-go-admin
      - ./fork260506-go-admin-core:/workspace/fork260506-go-admin-core
      - ./fork260506-gorm-adapter:/workspace/fork260506-gorm-adapter
      - ./fork260506-redis-watcher:/workspace/fork260506-redis-watcher
      - ./fork260506-redisqueue:/workspace/fork260506-redisqueue
      - ./go.work:/workspace/go.work:ro
      - ./scripts/backend-entrypoint.sh:/usr/local/bin/backend-entrypoint.sh:ro
      - ./config/settings.workspace-mysql.yml:/config/settings.yml:ro
      - go-mod-cache:/go/pkg/mod
    networks:
      workspace-net:
        aliases: [go-admin-backend]
    depends_on:
      migrate: { condition: service_completed_successfully }

  # ═══ sqlite profile ══════════════════════════════════════════════════════
  go-admin-sqlite:
    <<: *backend-base
    container_name: go-admin-sqlite
    profiles: [sqlite]
    ports: ["8000:8000"]
    command: ["server", "-c", "/config/settings.yml"]
    volumes:
      - ./fork260506-go-admin:/workspace/fork260506-go-admin
      - ./fork260506-go-admin-core:/workspace/fork260506-go-admin-core
      - ./fork260506-gorm-adapter:/workspace/fork260506-gorm-adapter
      - ./fork260506-redis-watcher:/workspace/fork260506-redis-watcher
      - ./fork260506-redisqueue:/workspace/fork260506-redisqueue
      - ./go.work:/workspace/go.work:ro
      - ./scripts/backend-entrypoint.sh:/usr/local/bin/backend-entrypoint.sh:ro
      - ./config/settings.workspace-sqlite.yml:/config/settings.yml:ro
      - ./config/go-admin-db.db:/go-admin-db.db
      - go-mod-cache:/go/pkg/mod
    networks:
      workspace-net:
        aliases: [go-admin-backend]

volumes:
  mysql-data:
  go-mod-cache:
  node-modules-go-admin-ui:

networks:
  workspace-net:
    driver: bridge
```

Use the Write tool with the absolute path `/mnt/d/AnewSpaces/Local/x_Project/TEST-claude/fork-go-admin/docker-compose.yml`.

- [ ] **Step 2: Validate the mysql profile**

```bash
docker compose --profile mysql config > /tmp/compose-mysql.yml && echo "mysql profile OK"
```

Expected: `mysql profile OK` (no warnings, no errors). The expanded yaml in `/tmp/compose-mysql.yml` should list 4 services: `mysql`, `migrate`, `go-admin-mysql`, `go-admin-ui`.

- [ ] **Step 3: Validate the sqlite profile**

```bash
docker compose --profile sqlite config > /tmp/compose-sqlite.yml && echo "sqlite profile OK"
```

Expected: `sqlite profile OK`. The expanded yaml should list 2 services: `go-admin-sqlite`, `go-admin-ui`.

- [ ] **Step 4: Spot-check service counts**

```bash
docker compose --profile mysql config --services | sort | tr '\n' ' '
echo
docker compose --profile sqlite config --services | sort | tr '\n' ' '
```

Expected output:
```
go-admin-mysql go-admin-ui migrate mysql 
go-admin-sqlite go-admin-ui 
```

- [ ] **Step 5: Verify network alias renders**

```bash
docker compose --profile mysql config | grep -A1 'go-admin-mysql:' | grep -A2 'aliases'
```

Expected: shows `- go-admin-backend` somewhere under `go-admin-mysql`'s networks block.

- [ ] **Step 6: Commit**

```bash
git add docker-compose.yml
git commit -m "$(cat <<'EOF'
feat(workspace): add docker-compose.yml with mysql/sqlite profiles

Single workspace-level compose file:
- yaml anchor &backend-base for shared image/env/entrypoint
- mysql profile (4 svc): mysql + migrate + go-admin-mysql + go-admin-ui
- sqlite profile (2 svc): go-admin-sqlite + go-admin-ui
- All 7 fork260506-* sub-repos bind-mounted; backend resolves libs via go.work
- China mirrors (GOPROXY, GOSUMDB, npmmirror, cnpm) commented for Taiwan default

Implements spec §3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Smoke test — mysql profile end-to-end

> This task does NOT modify files. It exercises the stack to verify it boots and serves. Each step is a verification command.

- [ ] **Step 1: Start mysql, wait for healthy**

```bash
docker compose --profile mysql up -d mysql
for i in $(seq 1 60); do
  status=$(docker compose --profile mysql ps mysql --format json 2>/dev/null | python3 -c "import sys,json; d=json.loads(sys.stdin.read() or '{}'); print(d.get('Health',''))" 2>/dev/null || echo "")
  if [ "$status" = "healthy" ]; then
    echo "mysql healthy after ${i}x5s"
    break
  fi
  sleep 5
done
docker compose --profile mysql ps mysql
```

Expected: `STATUS` column shows `Up X seconds (healthy)` within ~30–60s of first boot

- [ ] **Step 2: Run migrate (one-shot)**

```bash
docker compose --profile mysql up migrate
```

Expected:
- migrate container logs show go-admin migration messages (Chinese log lines such as `已迁移到最新版本` or English `migrate success`)
- Container exits with code 0
- After exit: `docker compose --profile mysql ps -a migrate` shows `Exited (0)`

If `connect: connection refused` appears: re-run `docker compose --profile mysql up migrate` once (mysql healthcheck has `start_period: 30s` but go-admin's own internal connect timeout may be tighter on cold start).

- [ ] **Step 3: Start backend + frontend**

```bash
docker compose --profile mysql up -d go-admin-mysql go-admin-ui
```

Expected: two new containers running:
```bash
docker compose --profile mysql ps go-admin-mysql go-admin-ui
```
Both `STATUS: Up X seconds`.

- [ ] **Step 4: Verify backend listens on :8000**

```bash
docker compose --profile mysql logs --tail=200 go-admin-mysql | grep -E "Listening|HTTP|:8000" | head -3
```

Expected: at least one line containing `Listening and serving HTTP on :8000` or similar gin startup banner. First boot may take 2–5 minutes (`go run` cold-compiles).

If no banner after 5 minutes, check:
```bash
docker compose --profile mysql logs --tail=100 go-admin-mysql
```
Look for go module download progress, CGO build messages, or panics.

- [ ] **Step 5: Verify backend reachable from host**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/api/v1/captcha
```

Expected: `200` (captcha endpoint is public on go-admin)

- [ ] **Step 6: Verify frontend dev server**

```bash
docker compose --profile mysql logs --tail=200 go-admin-ui | grep -E "App running|Compiled successfully|Local:" | head -3
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/
```

Expected:
- log line such as `App running at: - Local:   http://localhost:8080/`
- `curl` returns `200`

First boot may take 5–15 minutes (`npm install` is slow without cnpm/npmmirror in Taiwan).

- [ ] **Step 7: (manual) Browser login**

Open `http://localhost:8080` in browser. Try the seed credentials documented in `fork260506-go-admin/README.md` (typically `admin / admin` or `admin / 123456`). Expected: successful login → dashboard.

If browser-only access fails but `curl` works: WSL2 port-forward issue. Run `wsl --shutdown` from Windows host and restart.

- [ ] **Step 8: Verify sub-repo cleanliness**

```bash
git -C fork260506-go-admin status --short
git -C fork260506-go-admin-core status --short
git -C fork260506-go-admin-ui status --short
```

Expected: all three commands print nothing (clean working tree). The bind-mount writes `temp/logs/` inside `fork260506-go-admin/`, but `temp/` is gitignored upstream. If `git status` shows tracked-file changes, that's a regression — investigate before continuing.

- [ ] **Step 9: Stop the stack (preserve volumes)**

```bash
docker compose --profile mysql down
docker compose --profile mysql ps
```

Expected: `ps` empty (or no project services). `docker volume ls | grep -E 'mysql-data|go-mod-cache|node-modules-go-admin-ui'` should still show the named volumes (preserved for next run).

- [ ] **Step 10: Commit (no-op — this task changed no tracked files)**

No commit. T8 is verification only.

---

## Task 9: Smoke test — sqlite profile end-to-end

- [ ] **Step 1: Start sqlite stack**

```bash
docker compose --profile sqlite up -d
docker compose --profile sqlite ps
```

Expected: 2 containers running: `go-admin-sqlite`, `go-admin-ui`.

- [ ] **Step 2: Verify backend opened sqlite db**

```bash
docker compose --profile sqlite logs --tail=200 go-admin-sqlite | grep -iE "sqlite|/go-admin-db.db" | head -3
docker compose --profile sqlite logs --tail=200 go-admin-sqlite | grep -E "Listening|:8000" | head -1
```

Expected:
- a log line referencing `/go-admin-db.db` or `sqlite` (driver init)
- `Listening and serving HTTP on :8000`

If you see `unable to open database file`: check that `<workspace>/config/go-admin-db.db` exists and bind mount path in compose matches.

- [ ] **Step 3: Verify CGO/sqlite linked correctly**

```bash
docker compose --profile sqlite exec go-admin-sqlite which sqlite3
docker compose --profile sqlite exec go-admin-sqlite which gcc
```

Expected: both print paths (e.g., `/usr/bin/sqlite3`, `/usr/bin/gcc`). Confirms the entrypoint's `apk add` ran successfully.

- [ ] **Step 4: Verify backend reachable from host**

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/api/v1/captcha
```

Expected: `200`

- [ ] **Step 5: Verify sqlite db write-back**

```bash
mtime_before=$(stat -c '%Y' config/go-admin-db.db)
sleep 2
curl -s http://localhost:8000/api/v1/captcha > /dev/null
sleep 2
mtime_after=$(stat -c '%Y' config/go-admin-db.db)
echo "before=$mtime_before after=$mtime_after"
```

Expected: `mtime_after >= mtime_before` (captcha endpoint may write to db; if not, log into the UI to force a write). The point is to confirm bind-mount is rw, not just that the captcha specifically writes.

- [ ] **Step 6: Verify go.work resolved by backend**

```bash
docker compose --profile sqlite exec go-admin-sqlite go env GOWORK
```

Expected: `/workspace/go.work` (Go discovered our workspace file).

- [ ] **Step 7: Stop**

```bash
docker compose --profile sqlite down
docker compose --profile sqlite ps
```

Expected: empty.

- [ ] **Step 8: Commit (no-op — verification only)**

No commit.

---

## Task 10: Final state hygiene

- [ ] **Step 1: Verify all 5 new files committed and workspace tree clean**

```bash
cd /mnt/d/AnewSpaces/Local/x_Project/TEST-claude/fork-go-admin
git status --short --branch
```

Expected: `## main...origin/main` (or `## main...origin/main [ahead N]`). No `??` (untracked) entries; no `M`/`A` in status.

If you see `??` for things like `temp/`, `data/`, or container artifacts, those are container-side outputs that escaped into a bind-mounted directory. Add to `.gitignore` as a follow-up — don't commit them.

- [ ] **Step 2: Verify spec'd file set is fully present**

```bash
ls -1 docker-compose.yml go.work config/settings.workspace-mysql.yml \
      config/settings.workspace-sqlite.yml config/go-admin-db.db \
      scripts/backend-entrypoint.sh
```

Expected: 6 lines, all files exist (no `cannot access` errors).

- [ ] **Step 3: Verify commit log shows the implementation arc**

```bash
git log --oneline -10
```

Expected (top-down, most recent first):
```
<hash> feat(workspace): add docker-compose.yml with mysql/sqlite profiles
<hash> chore(workspace): add backend-entrypoint.sh
<hash> chore(workspace): add settings.workspace-sqlite.yml
<hash> chore(workspace): add settings.workspace-mysql.yml
<hash> chore(workspace): add go.work for cross-module local resolution
<hash> chore(workspace): copy sqlite seed db to config/
<hash> docs(spec): add workspace docker-compose design (mysql/sqlite hybrid profiles)
<hash> chore: initialize workspace repo with fork260506 analysis docs
```

(8 commits total: spec + 6 impl tasks + workspace bootstrap.)

- [ ] **Step 4: Confirm all 7 fork260506-* sub-repos are still clean**

```bash
for d in fork260506-*/; do
  echo "=== $d ==="
  git -C "$d" status --short --branch
done
```

Expected: every sub-repo shows `## main...origin/main` and no further lines.

- [ ] **Step 5: Push? (gated — see global rule)**

Per user's global git rule, do NOT `git push` autonomously. Tell the user:

> "Implementation complete: 6 commits landed. Workspace and all sub-repos clean. Want me to push to origin?"

Wait for explicit confirmation. Only push after the user says yes.

---

## Self-Review

**Spec coverage check:**
- §0 Context → embedded in plan header + T2 explanation
- §1 Architecture → exercised in T8 (mysql) and T9 (sqlite)
- §2.1 tree → built by T1 (dirs), T2 (db), T3–T7 (5 files)
- §2.2 provenance → spec is reference, no impl needed
- §2.3 .gitignore unchanged → T10 step 1 verifies clean status
- §2.4 go.work → T3
- §2.5 settings-mysql.yml → T4
- §2.6 settings-sqlite.yml → T5
- §2.7 backend-entrypoint.sh → T6
- §3 docker-compose.yml → T7
- §4 Phase 0 prereqs → assumed before T1; user instructed to verify host docker / port availability before running
- §4 Phase 2 mysql bring-up → T8
- §4 Phase 3 sqlite switch → T9
- §4 Phase 4 cleanup → T9 step 7 + T10
- §5 troubleshooting → referenced inline at T8 step 2 (migrate retry) and T8 step 7 (WSL2)
- §6 verification → distributed across T8, T9, T10

**Placeholder scan:** No TBD/TODO/"add validation"/"similar to" patterns. Every step has either an exact command, an exact file write (with full content inline), or a verification recipe with expected output.

**Type/name consistency check:**
- service names `mysql` / `migrate` / `go-admin-mysql` / `go-admin-sqlite` / `go-admin-ui` — used uniformly across plan + spec
- container names `workspace-mysql` / `workspace-migrate` / `go-admin-mysql` / `go-admin-sqlite` / `go-admin-ui` — uniform
- network alias `go-admin-backend` — declared in T7 yaml, unchanged
- mount paths `/workspace/...` / `/config/settings.yml` / `/go-admin-db.db` — uniform
- volumes `mysql-data` / `go-mod-cache` / `node-modules-go-admin-ui` — uniform

No drift detected.
