# Workspace-Level docker-compose.yml — 設計文件

> **產出來源**:`superpowers:brainstorming` 流程
> **撰寫日期**:2026-05-08
> **語言**:zh-TW(繁體中文)
> **作者**:Claude Code(對話式產出,opus 4.7 1M context)
> **目標**:為 workspace 根 (`/mnt/d/AnewSpaces/Local/x_Project/TEST-claude/fork-go-admin/`)
>          打造一份 `docker-compose.yml`,以 bind-mount 方式加載 7 個 `fork260506-*`
>          子 repo,提供 hybrid (mysql / sqlite) 雙 profile 的 dev stack。

---

## 0. Context

### 0.1 為何需要這份 spec

當前 workspace 根目錄底下有 7 個獨立 git repo:

| Sub-repo | 角色 | 是否為服務 |
|---|---|---|
| `fork260506-go-admin` | Go backend 主程式(`main.go`) | ✅ Service |
| `fork260506-go-admin-ui` | Vue 2 frontend(`vue-cli-service serve`) | ✅ Service |
| `fork260506-go-admin-doc` | dumi 文件站 | ❌(本 spec 不掛 service,使用者排除) |
| `fork260506-go-admin-core` | Go SDK runtime 核心 lib | ❌ Library |
| `fork260506-gorm-adapter` | casbin gorm adapter lib | ❌ Library |
| `fork260506-redis-watcher` | casbin redis watcher lib | ❌ Library |
| `fork260506-redisqueue` | redis 隊列 lib | ❌ Library |

3 個是可跑的服務,4 個是 Go 函式庫,1 個 docs(本 spec 不掛 service)。
本 spec 的目的是在 workspace 根新增一份 `docker-compose.yml` + 配套設定檔,
讓使用者用一條指令把 dev stack 起起來,且支援 mysql / sqlite 兩種 DB driver。

4 個函式庫 repo 透過 workspace 級 `go.work` 被 backend 容器 bind-mount + 解析為
本機 module(優於 `go.mod replace` ── 不污染任何 sub-repo 的 git tree)。

### 0.2 Brainstorming 已確認的設計原則

- ✅ 完整 dev stack(不含 docs):mysql 4-svc / sqlite 2-svc hybrid via Compose profiles
- ✅ Workspace 自持 `settings.workspace-{mysql,sqlite}.yml`,bind-mount 到容器(不污染 sub-repo)
- ✅ 7 個 sub-repo 全部 bind-mount;backend 走 `go.work` 解析 lib(不寫 `go.mod replace`)
- ✅ 單檔 `docker-compose.yml` + Compose profiles(對 git review、新人 onboarding 最友善)
- ✅ 從 `fork260506-go-admin/go-admin-db.db` 拷貝 sqlite seed 到 `<workspace>/config/`,
     讓 schema 固化在 workspace 內進行
- ✅ Service 命名以 `-` 連結複合字(`go-admin-ui` / `go-admin-mysql` / `go-admin-sqlite`);單字 service 直接用(`mysql` / `migrate`)
- ✅ Taiwan 網路:中國 mirror 設定全部 `#` 註解但保留作參考(GOPROXY、GOSUMDB、npmmirror、cnpm)

### 0.3 範圍 / 非範圍

**範圍:**
- 單一 `docker-compose.yml`
- `go.work`(workspace 級 Go workspace,列 5 個 Go module repo)
- `config/settings.workspace-mysql.yml` + `config/settings.workspace-sqlite.yml`
- `config/go-admin-db.db`(從 sub-repo 拷貝的 sqlite seed)
- `scripts/backend-entrypoint.sh`(go.sum tidy fallback + apk add CGO toolchain)
- 本 spec 文件本身

**非範圍:**
- ❌ `go-admin-doc` (dumi) 容器化(使用者明確排除)
- ❌ Production build profile(`Dockerfilebak` 路線);`cosmtrek/air` 熱重載
- ❌ Redis 容器(redis-watcher、redisqueue 是 lib,本身不需要 redis broker)
- ❌ Postgres / SQLServer driver(只支援 mysql 與 sqlite 兩個 profile)
- ❌ 任何 fork260506-* sub-repo 內的檔案修改

---

## 1. 架構與 service 拓撲

### 1.1 Mysql profile(`docker compose --profile mysql up -d`)— 4 services

```
┌──────────┐ port 8080  ┌──────────────┐  /api/*    ┌─────────────┐
│ Browser  │──────────▶│ go-admin-ui   │──────────▶│ go-admin-    │
│ (host)   │            │ vue-cli serve │ (proxy)    │ mysql        │
└──────────┘            │ node:18-      │            │ go run       │
                        │  alpine       │            │ golang:1.24- │
                        └──────────────┘            │  alpine      │
                                                    └──────┬───────┘
                                                           │ mysql:3306
                                                           ▼
                                       ┌──────────┐ one-shot ┌──────────┐
                                       │ migrate  │────────▶ │ mysql    │
                                       │ go run   │ exits 0  │ 8.0      │
                                       │ migrate  │          │ + named  │
                                       └──────────┘          │ vol      │
                                                             └──────────┘
```

依賴鏈:`mysql` healthy → `migrate` 跑完退出 → `go-admin-mysql` 啟動 → `go-admin-ui`(無依賴,可並啟)。

### 1.2 SQLite profile(`docker compose --profile sqlite up -d`)— 2 services

```
┌──────────┐ port 8080  ┌──────────────┐  /api/*    ┌─────────────┐
│ Browser  │──────────▶│ go-admin-ui   │──────────▶│ go-admin-    │
│ (host)   │            │ vue-cli serve │            │ sqlite       │
└──────────┘            └──────────────┘            │ go run       │
                                                    │ + go-admin-  │
                                                    │  db.db       │
                                                    │ (bind mount) │
                                                    └─────────────┘
```

無依賴鏈,`go-admin-sqlite` 與 `go-admin-ui` 可並啟。

### 1.3 兩種 mode 共用的 service(無 profile)

| Service | Image | Ports(host:container) | Bind mounts |
|---|---|---|---|
| `go-admin-ui` | `node:18-alpine` | `8080:8080` | `./fork260506-go-admin-ui:/app` + named volume `node-modules-go-admin-ui:/app/node_modules` |

### 1.4 兩個 backend service(共用 yaml anchor `&backend-base`)

| Service | Profile | command | settings 來源 | depends_on |
|---|---|---|---|---|
| `go-admin-mysql` | `mysql` | `["server", "-c", "/config/settings.yml"]`(`go run` 由 entrypoint script 統一) | bind-mount `./config/settings.workspace-mysql.yml` | `migrate`(`condition: service_completed_successfully`) |
| `go-admin-sqlite` | `sqlite` | 同上 | bind-mount `./config/settings.workspace-sqlite.yml`(+ `./config/go-admin-db.db:/go-admin-db.db`) | (無) |

### 1.5 Mysql-only services

| Service | Image | command | profile |
|---|---|---|---|
| `mysql` | `mysql:8.0`(`--character-set-server=utf8mb4`、`--innodb-default-row-format=DYNAMIC`) | (image default) | `mysql` |
| `migrate` | `golang:1.24-alpine` | `["migrate", "-c", "/config/settings.yml"]`(一次性,exit 0 後不 restart) | `mysql` |

### 1.6 Port 配置

- `8080:8080` → `go-admin-ui`(瀏覽器入口,**必須 expose**)
- `8000:8000` → `go-admin-mysql` / `go-admin-sqlite`(**仍 expose 給 host**,因 `vue.config.js` 沒設 `devServer.proxy`,瀏覽器直接打 `VUE_APP_BASE_API=http://localhost:8000`)
- `mysql:3306` → 不 expose(只在 compose network 內)

> `vue.config.js:36-45` 沒有 `devServer.proxy` 設定,所以 frontend 不會代理 `/api/*` 到 backend;
> 瀏覽器自行打 backend 8000 port。這是 host 必須 expose 8000 的根本原因。

---

## 2. 檔案結構與新增檔清單

### 2.1 Workspace tree(套用本 spec 後最終樣貌)

```
fork-go-admin/                                        ← workspace 根
├── .git/  .gitignore  CLAUDE.md  fork260506*.md       ← 既有
│
├── docker-compose.yml                                ← 🆕 hybrid profiles 主檔(§3)
├── go.work                                           ← 🆕 Go workspace,列 5 個 Go module repo(§2.4)
│
├── config/                                           ← 🆕 workspace 自持 backend 設定 + sqlite 種子
│   ├── settings.workspace-mysql.yml                  ← 🆕(§2.5)
│   ├── settings.workspace-sqlite.yml                 ← 🆕(§2.6)
│   └── go-admin-db.db                                ← 🆕(從 fork260506-go-admin/go-admin-db.db 拷貝)
│
├── docs/superpowers/specs/                           ← 🆕 spec 目錄
│   └── 20260508a_workspace-docker-compose-design.md  ← 🆕 本 spec
│
├── scripts/                                          ← 🆕
│   └── backend-entrypoint.sh                         ← 🆕(§2.7)
│
└── fork260506-*/                                     ← 既有 7 個 sub-repo,完全不動
```

### 2.2 Source provenance matrix(本設計取材自以下檔案)

| 來源檔 | 分支 | 取用內容 | 用在 workspace 的哪裡 |
|---|---|---|---|
| `fork260506-go-admin/config/settings.yml` | main | mysql template 骨架 | `settings.workspace-mysql.yml` 基底 |
| `fork260506-go-admin/config/settings.full.yml` | main | mysql 完整版(ssl、registers、cache 段) | `settings.workspace-mysql.yml` 補完 |
| `fork260506-go-admin/config/settings.sqlite.yml` | main(與 001 內容相同;`git diff main..001` 為空) | sqlite minimal template | `settings.workspace-sqlite.yml` 基底 |
| `fork260506-go-admin/config/settings.demo.yml` | main | (參考但不採用) — sqlite + demo mode + extend.amap | — |
| `fork260506-go-admin/Dockerfile.learning` | 001-learning-trace-login | multi-stage build pattern + `go mod tidy` 解 go.sum gitignored 問題 | `scripts/backend-entrypoint.sh` 的 fallback 邏輯 |
| `fork260506-go-admin/Dockerfile` | main | (參考但不採用) — 預編 binary 路線 | — |
| `fork260506-go-admin/Dockerfilebak` | main | (參考但不採用) — multi-stage `go build` 完整流程(GOPROXY、CGO_ENABLED=0、ldflags `-w -s`) | 未來 `--profile prod-build` 範圍 |
| `fork260506-go-admin/docker-compose.yml` | main | 既有 in-repo compose;bridge network、container_name 命名習慣 | network 設計參考(`workspace-net`) |
| `fork260506-go-admin-ui/Dockerfile` | main | cnpm + npmmirror + multi-stage build:prod | `go-admin-ui.command` 註解掉的 mirror 路徑(中國網路用) |
| `fork260506-go-admin-ui/vue.config.js` | main | `devServer.port` 預設 9527、無 `devServer.proxy` | 確定 frontend 容器需設 `port=8080` env、確定 backend 需 expose 8000 |
| `fork260506-go-admin-doc/docs/superpowers/spec/2026-05-07-learning-docs.md` | main | 4-service stack 拓撲、healthcheck 配方、named volume cache、port forward 注意事項、故障排除 matrix | docker-compose.yml 整體骨架、§4 啟動流程、§5 故障排除 |
| `fork260506-go-admin/go-admin-db.db` | main | sqlite seed 檔(348 KB) | 拷貝到 `config/go-admin-db.db` |

### 2.3 `.gitignore` 不需動

現有 `<workspace>/.gitignore`:

```
_temp_
fork260506-*
```

新增物 `docker-compose.yml`、`go.work`、`config/`、`docs/`、`scripts/` 都不在忽略清單,
會被 workspace repo 自動追蹤。`config/go-admin-db.db`(348 KB binary)直接 git 追蹤;
若未來體積成長(>1 MB)再評估 git LFS。

### 2.4 `go.work`

```
go 1.25

use (
    ./fork260506-go-admin
    ./fork260506-go-admin-core
    ./fork260506-gorm-adapter
    ./fork260506-redis-watcher
    ./fork260506-redisqueue
)
```

`fork260506-go-admin-ui`(Vue)與 `fork260506-go-admin-doc`(dumi)非 Go module,不進 `go.work`。

backend 容器 `working_dir: /workspace/fork260506-go-admin`;從那裡 Go 自動往上找到
`/workspace/go.work`,進入 workspace mode,把 `import "github.com/go-admin-team/go-admin-core/..."`
等 import 路徑解析到本機 `/workspace/fork260506-go-admin-core/`(而不是 module cache 裡
從 GitHub 抓的版本)。

### 2.5 `config/settings.workspace-mysql.yml`(完整內容)

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
    # 單位:秒 (server.go:92-93 用 time.Duration(...) * time.Second)
    # 上游 settings.yml 是 1 秒(太短),settings.sqlite.yml 是 3000 秒(50 分鐘,過長 mask 住 hang);
    # workspace 取折衷的 30 秒。
    readtimeout: 30
    writertimeout: 30
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

### 2.6 `config/settings.workspace-sqlite.yml`(完整內容)

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
    # 單位:秒 (server.go:92-93 用 time.Duration(...) * time.Second)
    # 上游 settings.yml 是 1 秒(太短),settings.sqlite.yml 是 3000 秒(50 分鐘,過長 mask 住 hang);
    # workspace 取折衷的 30 秒。
    readtimeout: 30
    writertimeout: 30
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

### 2.7 `scripts/backend-entrypoint.sh`(完整內容)

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

執行權限:`chmod +x scripts/backend-entrypoint.sh`(Phase 1 步驟之一)。

---

## 3. `docker-compose.yml` 完整內容

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
    image: node:18-alpine                        # learning-docs §1 用 16.15;升 18 LTS
    container_name: go-admin-ui
    working_dir: /app
    ports: ["8080:8080"]
    volumes:
      - ./fork260506-go-admin-ui:/app            # source bind-mount (改 code 立即生效)
      - node-modules-go-admin-ui:/app/node_modules  # named vol (npm install 結果在此快取)
    environment:
      port: "8080"                               # vue.config.js:17 讀 process.env.port (預設 9527 → 8080)
      VUE_APP_BASE_API: http://localhost:8000    # vue.config.js 無 devServer.proxy,瀏覽器直打 backend
      TZ: Asia/Shanghai
    command:
      - sh
      - -c
      - |
        if [ ! -d node_modules ] || [ -z "$$(ls -A node_modules 2>/dev/null)" ]; then
          # ─── 中國網路 mirror (Taiwan 不需要,留作參考) ───
          # npm config set registry https://registry.npmmirror.com   # from: fork260506-go-admin-ui/Dockerfile:4
          # npm install -g cnpm --registry=https://registry.npmmirror.com
          # cnpm install
          npm install
        fi
        npm run dev
    networks: [workspace-net]

  # ═══ mysql profile ═══════════════════════════════════════════════════════
  mysql:
    image: mysql:8.0                             # learning-docs §1
    container_name: workspace-mysql
    profiles: [mysql]
    command:
      - --character-set-server=utf8mb4           # learning-docs §6.1 InnoDB key length 預防
      - --collation-server=utf8mb4_unicode_ci
      - --innodb-default-row-format=DYNAMIC      # learning-docs §6.1
    environment:
      MYSQL_ROOT_PASSWORD: rootpw                # 僅 dev,生產自行覆寫
      MYSQL_DATABASE: go-admin                   # 對齊 settings.workspace-mysql.yml DSN
      MYSQL_USER: go-admin
      MYSQL_PASSWORD: go-admin123
      TZ: Asia/Shanghai
    volumes:
      - mysql-data:/var/lib/mysql                # named vol,docker compose down 不刪
    healthcheck:                                 # learning-docs §6.2:等 mysql 真 ready
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
    restart: "no"                                # 一次性,跑完就退出
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
      - go-mod-cache:/go/pkg/mod                 # named vol,共用 go module cache
    depends_on:
      mysql: { condition: service_healthy }      # learning-docs §6.2

  go-admin-mysql:
    <<: *backend-base
    container_name: go-admin-mysql
    profiles: [mysql]
    ports: ["8000:8000"]                         # 暴露 host:8000,瀏覽器直打
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
        aliases: [go-admin-backend]              # 穩定 DNS alias (與 sqlite 共用)
    depends_on:
      migrate: { condition: service_completed_successfully }

  # ═══ sqlite profile ══════════════════════════════════════════════════════
  go-admin-sqlite:
    <<: *backend-base
    container_name: go-admin-sqlite
    profiles: [sqlite]
    ports: ["8000:8000"]                         # 與 mysql 共用 host port (兩 profile 不同時跑)
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
      - ./config/go-admin-db.db:/go-admin-db.db  # rw,允許 runtime 寫;workspace 持有
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

### 3.1 重點設計決策

1. **CGO toolchain 安裝在 entrypoint** — sqlite 需 CGO,`golang:1.24-alpine` 沒 gcc。
   entrypoint 用 `apk add gcc g++ libc6-compat sqlite tzdata` 補上。
   `docker compose stop/start` 保留容器 → 不重裝;`down/up` 重建 → 會重裝(額外 ~30s)。

2. **Network alias `go-admin-backend`** — 兩個 backend 變體在 compose net 內都註冊此別名。
   當前瀏覽器走 `localhost:8000`,將來若改 `vue.config.js` proxy,可指向
   `go-admin-backend:8000` 而不需區分 profile。

3. **Port 共用 8000** — `go-admin-mysql` 與 `go-admin-sqlite` 都 expose `8000:8000`。
   設計意圖是兩個 profile 不同時啟用;Compose profiles 本身不強制互斥(若使用者同時帶
   `--profile mysql --profile sqlite`,後啟者會在 host port 8000 衝突而失敗,等於由 OS
   層級擋下而非 compose 層級)。

4. **`<<: *backend-base` 範圍受限** — yaml merge 只動 mapping。`volumes` / `command` /
   `ports` / `depends_on` / `container_name` / `profiles` 在 3 個 backend service 都得各自寫。
   看似重複,但 yaml 結構受限,且讓每個 service 自我完整、可獨立 review。

5. **沒有 frontend healthcheck** — `vue-cli-service serve` 沒有方便的 health endpoint;
   前端是否 ready 由瀏覽器訪問驗證(對應 learning-docs §7.1)。

6. **沒走 `docker build`** — 完全 bind-mount + `go run` / `npm run dev` 路線(對齊
   learning-docs.md);不產生中間 image。要走 prod build 屬未來 `--profile prod-build` 範圍。

---

## 4. 啟動驗證流程(對齊 learning-docs.md Phase 風格)

### Phase 0 — 前置檢查(2 分鐘)

```bash
docker version
docker compose version            # 必為 v2 / plugin 形式
ss -ltn | grep -E ':8000|:8080'   # 應該無輸出 (兩 port 未被佔用)
```

- [ ] `docker compose version` 通過(必為 v2)
- [ ] host port 8000、8080 無人在聽

### Phase 1 — 落地 spec 檔案(5 分鐘,首次)

在 workspace 根:

```bash
# (a) 建立目錄
mkdir -p config docs/superpowers/specs scripts

# (b) 拷貝 sqlite seed db (workspace 自持,讓 schema 固化在 workspace 內)
cp fork260506-go-admin/go-admin-db.db config/go-admin-db.db

# (c) 寫入下列檔案 (內容見 §2.4 / §2.5 / §2.6 / §2.7 / §3):
#     - go.work
#     - config/settings.workspace-mysql.yml
#     - config/settings.workspace-sqlite.yml
#     - scripts/backend-entrypoint.sh
#     - docker-compose.yml

# (d) 執行權限
chmod +x scripts/backend-entrypoint.sh

# (e) 驗證 compose 設定可解析
docker compose --profile mysql config > /dev/null && echo "mysql profile OK"
docker compose --profile sqlite config > /dev/null && echo "sqlite profile OK"
```

- [ ] 5 個新檔皆建立
- [ ] `config/go-admin-db.db` 拷貝完成(348 KB)
- [ ] `chmod +x scripts/backend-entrypoint.sh`
- [ ] 兩個 `docker compose ... config` 都印出 OK,無 error

### Phase 2 — 啟動 mysql profile(首次 5–15 分鐘,主要等 npm install + go module download)

```bash
# (a) 起 mysql 並等 healthy
docker compose --profile mysql up -d mysql
docker compose --profile mysql ps              # mysql 應顯示 (healthy)

# (b) 跑一次性 migrate (前景看 logs)
docker compose --profile mysql up migrate      # 應 exit 0

# (c) 起 backend + frontend
docker compose --profile mysql up -d go-admin-mysql go-admin-ui
docker compose --profile mysql logs -f go-admin-mysql go-admin-ui  # Ctrl+C 停 follow
```

驗證:
- [ ] `mysql` STATUS 顯示 `Up (healthy)`
- [ ] `migrate` 容器 exit code = 0
- [ ] backend log 出現 `Listening and serving HTTP on :8000`
- [ ] frontend log 出現 `App running at http://localhost:8080/`
- [ ] 瀏覽器 `http://localhost:8080` 看到 go-admin 登入畫面
- [ ] 用上游預設帳密登入成功(以 fork260506-go-admin/README 為準,通常 `admin / admin` 或 `admin / 123456`)

### Phase 3 — 切到 sqlite profile

```bash
# (a) 收 mysql profile (保留 mysql-data named vol)
docker compose --profile mysql down

# (b) 起 sqlite profile
docker compose --profile sqlite up -d
docker compose --profile sqlite logs -f
```

驗證:
- [ ] `go-admin-sqlite` log 顯示 sqlite 連線成功(無 mysql connect error)
- [ ] 瀏覽器 `http://localhost:8080` 仍能登入(用 sqlite seed db 內既有帳密)

### Phase 4 — 收工

```bash
# (a) 暫停但保留 named volumes
docker compose --profile mysql down
# 或
docker compose --profile sqlite down

# (b) 完全 reset (連 named vol 一起刪)
docker compose --profile mysql down -v
```

---

## 5. 故障排除速查(改編自 learning-docs §9)

| 症狀 | 最可能原因 | 修法 |
|---|---|---|
| `docker compose config` 報 `service "go-admin-mysql" depends on undefined service "migrate"` | profile 沒帶 mysql | 用 `--profile mysql` 才能讓 migrate 被視為 active |
| `mysql` 一直 unhealthy | mysql 8 認證 plugin 衝突 / volume 殘留 | `docker compose down -v` 清掉 mysql-data 後重來 |
| `migrate` 退出 code != 0,`connect: connection refused` | mysql 還沒 fully ready,healthcheck retry 不夠 | `start_period: 30s` 已加長;首次仍可能要 `up migrate` 再跑一次 |
| `migrate` 退出 code != 0,`Access denied for user` | settings.workspace-mysql.yml 帳密與 compose env 不一致 | 對齊 `go-admin / go-admin123 / go-admin` 三件套 |
| backend 啟動 panic `bind: address already in use` | host 8000 已佔用(可能是另一 profile 沒收乾淨) | `docker compose --profile mysql down` 與 `--profile sqlite down` 都跑一遍 |
| backend 啟動 OK 但瀏覽器打不到 `/api/*` | `VUE_APP_BASE_API` 沒生效或 backend 沒 expose 8000 | 檢查 docker ps 顯示 `0.0.0.0:8000->8000/tcp` |
| backend 啟動但 `missing go.sum entry` | go.sum 缺失且 entrypoint script 沒跑 tidy | 確認 `scripts/backend-entrypoint.sh` 有 `chmod +x`;進容器看 `cat /usr/local/bin/backend-entrypoint.sh` |
| sqlite backend 啟動但 `unable to open database file` | bind-mount 路徑錯;權限不足 | 確認 `<workspace>/config/go-admin-db.db` 存在;改 mount 為 `:rw`(預設就是 rw) |
| sqlite backend `Binary was compiled with 'CGO_ENABLED=0'` | apk add 失敗 / entrypoint 跳過了 install | 進容器跑 `which gcc`;若無則手動 `apk add gcc g++ libc6-compat sqlite` |
| frontend `npm install` 卡死 | npm 對 alpine glibc 套件編譯失敗 | 改用 `node:18-bullseye-slim`(debian-based)替代 alpine |
| frontend dev server 起在 9527 不是 8080 | env `port=8080` 沒注入 | docker-compose.yml 的 `go-admin-ui.environment.port` 必為字串 `"8080"` |
| 瀏覽器登入看到 CORS 錯誤 | 後端沒設 CORS,前端與後端走不同 origin | 短期解:browser 安裝 CORS 擴充;長期解:在 `vue.config.js` 加 `devServer.proxy` |
| WSL2 主機 Windows 瀏覽器開不到 | WSL2 自動 forward 失效 | WSL 內 `curl localhost:8080` 確認;不行則 `wsl --shutdown` 重啟 |

---

## 6. 驗證(spec 落地後該測什麼)

| 檔案 / 行為 | 怎麼驗證 |
|---|---|
| `docker-compose.yml` 語法 | `docker compose --profile mysql config` 與 `--profile sqlite config` 都印 OK |
| `go.work` 解析 | 進 `go-admin-mysql` 容器跑 `go env GOWORK` 應顯示 `/workspace/go.work` |
| `settings.workspace-mysql.yml` 載入 | backend log 顯示 `mysql: connected to mysql:3306/go-admin` |
| `settings.workspace-sqlite.yml` 載入 | backend log 顯示 `sqlite: opened /go-admin-db.db` |
| `config/go-admin-db.db` 寫入 | sqlite mode 登入 → host 端 `stat config/go-admin-db.db` mtime 更新 |
| `backend-entrypoint.sh` `go mod tidy` 路徑 | 移除 fork260506-go-admin/go.sum 後重啟,容器仍能起來 |
| Profile 互斥 | mysql profile up 時 sqlite container 不存在(`docker ps` 不見) |
| Sub-repo 不被污染 | 跑完整流程後 `git -C fork260506-go-admin status` 仍乾淨 |
| Workspace repo 追蹤新檔 | `git -C <workspace> status` 顯示 5 個新檔 untracked / staged |

---

## 7. 修訂紀錄

| 日期 | 修改 | 作者 |
|---|---|---|
| 2026-05-08 | 初版(brainstorming 產出) | Claude Code |
