# fork260506-* 改寫成 Rust 的可能性評估

評估日期:2026-05-07

## 結論摘要

七個 repo 中 **2 個不是 Go 專案**(`go-admin-doc` 是 dumi 靜態文件站、`go-admin-ui` 是 Vue 3 前端),本身就不在「Go → Rust 改寫」範圍。實際待評估的是 **5 個 Go repo**。

## 規模與性質

| Repo | LOC | go 版 | 性質 | 改寫策略建議 |
|---|--:|---|---|---|
| **go-admin** | 18,204 | 1.24 | 上層 admin 應用 (Gin + Casbin + JWT + OSS + Sentinel) | ⚠️ 高成本 |
| **go-admin-core** | 17,884 | 1.25 | 應用框架 SDK (auth/cache/captcha/orm/jwt/...) | ⚠️ 高成本 |
| **gorm-adapter** | 1,547 | 1.14 | Casbin 的 GORM adapter | ❌ 不建議改寫,改用既有 Rust crate |
| **redis-watcher** | 811 | 1.20 | Casbin 的 Redis pub/sub watcher | ❌ 不建議改寫,改用既有 Rust crate |
| **redisqueue** | 1,362 | 1.20 | Redis Streams 佇列函式庫 | △ 自己包薄層 |
| go-admin-doc | 0 | – | dumi 靜態文件 | N/A (非 Go) |
| go-admin-ui | 0 | – | Vue 3 前端 | N/A (非 Go) |

實際 Go 程式碼總量 **≈ 39.8k LOC**,集中在 go-admin + go-admin-core(共佔 90%)。

## 關鍵 Go 依賴的 Rust 對應

### 有成熟對應(直接替換)

| Go | Rust |
|---|---|
| gin / fiber | **axum** / actix-web |
| gorm | **sea-orm** / sqlx / diesel |
| casbin/casbin-go | **casbin-rs**(官方) |
| redis/go-redis/v9 | **redis-rs** / fred |
| golang-jwt/jwt | **jsonwebtoken** |
| fsnotify | **notify** |
| BurntSushi/toml + ghodss/yaml + bitly/go-simplejson | toml / serde_yaml / serde_json |
| mssola/user_agent | ua_parser / woothee |
| prometheus client_golang | prometheus / metrics |
| opentracing | **opentelemetry**(順便升 OTel,opentracing 已 deprecated) |
| go-playground/validator | validator |

### Rust 生態缺口(需自製或繞路)

| Go 依賴 | 問題 |
|---|---|
| **aliyun-oss-go-sdk** | 阿里雲沒釋出官方 Rust SDK,需自己包 REST(或用 `rusoto` 風格社群 crate,品質參差) |
| **huaweicloud-sdk-go-obs** | 同上,華為雲也沒官方 Rust SDK |
| **alibaba/sentinel-golang** | 流量控制/熔斷,Rust 端無等價 — 可改用 `tower::limit` + `tower::circuit-breaker` 自組,但語義不同 |
| **bytedance/go-tagexpr/v2** | tag 表達式驗證,Rust 用 `validator` 替代,但 DSL 不同需重寫所有規則 |
| **chanxuehong/wechat** | 微信 SDK,Rust 社群有零星 crate 但完整度低 |
| **golang/freetype** | Captcha 用,Rust 有 `rusttype` / `ab_glyph`,但 API 完全不同 |

## 三大隱性成本

### 1. Fork 同步性立刻消失(最大風險)

這七個都是上游 fork,專案的 graphify 報告與 SpecKit constitution(`Principle II 跨 fork hygiene`)明白要求**保留上游可追溯性**。改寫成 Rust 等於切斷上游 — 之後 casbin、go-admin、go-admin-core、gorm-adapter 上游修 bug、加功能,你都得自己 port,且 port 不再是「cherry-pick」而是「翻譯」。**這跟 constitution Principle II 直接衝突**。

### 2. 三個 Casbin 生態小庫改寫沒意義

`gorm-adapter` / `redis-watcher` 在 Rust 端有對應實作 — `casbin-rs` 官方已提供 `sqlx-adapter`、`diesel-adapter`、`redis-watcher`(同名)。**「改寫」的正確替代是「在 Rust 專案中直接 import 對應 crate」**,連寫都不用寫,改 fork 反而是負擔。

### 3. 跨 repo 改寫順序綁手綁腳

依賴鏈:`go-admin → go-admin-core + gorm-adapter + redis-watcher → casbin-rs/sea-orm/redis-rs`。必須由下而上做,且中途無法部分上線(go-admin-core 的 Rust 版做好之前,go-admin 的 Rust 版根本跑不起來)。

## 工時粗估

僅供量級參考,實際依團隊熟悉度浮動。

| 階段 | 工作量 | 工時 |
|---|---|---|
| 三個小庫:**用既有 crate 替代,不改寫** | 寫接線層 | ~1 週 |
| go-admin-core 改寫 (~18k LOC,含 ORM 模型/auth/captcha/cache 全部重做) | 大重構 | **2–4 人月** |
| go-admin 改寫 (~18k LOC,含路由/中介層/業務模組) | 大重構 | **2–4 人月** |
| 阿里雲 OSS / 華為雲 OBS 自製 SDK | 自寫 + 測試 | **0.5–1 人月** |
| Sentinel 替代方案設計與驗證 | 設計密集 | **0.5 人月** |
| 整合測試、效能比對、上線過渡期(雙跑) | 收斂 | **1–2 人月** |
| **總計** | | **≈ 6–12 人月** |

## 建議

**先不要改寫,先回答「為什麼要改寫」**:

| 動機 | 是否合理? |
|---|---|
| 效能瓶頸(Go GC、記憶體佔用) | ⚠️ 先 profile,go-admin 這類 admin 後台多半瓶頸在 DB/Redis,不在語言 |
| 記憶體安全/併發安全 | ❌ Go 已有相當安全保證,改 Rust 收益主要是 unsafe 邊界更嚴 |
| 部署體積/啟動速度 | △ Rust 確實更小更快,但 Go 已經是 single binary,差距有限 |
| 團隊偏好/招募 | ⚠️ 招 Rust 全端工程師比招 Go 難 |
| 上游已經沒在維護 | ✅ 這是最強動機,但要先確認上游真的死了 |

**如果一定要動**,建議的最小可行路徑:

1. **保留 go-admin-doc / go-admin-ui 不動**(本來就不是 Go)
2. **三個 Casbin 小庫**:不改寫,在 Rust 新專案中直接 import `casbin-rs` 生態 crate
3. **先試做 go-admin-core 的一個子模組**(如 auth + jwt)做 PoC,跑 1–2 週,實測:Rust 寫起來真的有比較好嗎?第三方依賴的破口能補上嗎?
4. PoC 通過再決定是否擴張;PoC 不通過就停。

**最划算的可能不是「改寫」,而是「停在 Go,把 fork 收斂上游」** — 因為光是維持 fork 同步性的成本,就跟改寫成 Rust 後永遠脫離上游的代價在同一個數量級。

---

# 附錄:逐模組對應表(go-admin & go-admin-core)

範圍:`fork260506-go-admin`(應用層,18,204 LOC)+ `fork260506-go-admin-core`(框架 SDK,17,884 LOC)

複雜度標示:
- 🟢 **低**:有 1:1 成熟 crate,基本是「翻譯」
- 🟡 **中**:概念對應但 API 差異大,需重新設計
- 🟠 **高**:Rust 生態缺對應或 DSL 不同,需自製
- 🔴 **極高**:無上游 SDK,需自寫整層

---

## Part 1 — `fork260506-go-admin-core` 模組對應(框架 SDK)

### 1.1 配置系統

| Go 模組 | 職責 | Go 依賴 | Rust 對應 | 複雜度 | 風險點 |
|---|---|---|---|---|---|
| `config/` (頂層 `Config`/`Reader`/`Value` 介面) | 多 source / encoder / loader 的配置抽象 | 自製 | **`config` crate** 或 **`figment`** | 🟡 中 | 既有抽象比 config crate 多一層;直接擁抱 figment 的 `Provider` 模型較自然 |
| `config/encoder/` (json/yaml/toml/xml) | 多格式編解碼 | encoding/json, BurntSushi/toml, ghodss/yaml | `serde_json` / `toml` / `serde_yaml` / `quick-xml` | 🟢 低 | xml 用得不多 |
| `config/loader/` | 載入策略 | 自製 | figment 的 layered providers | 🟡 中 | 設計改動,API 不可向下相容 |
| `config/reader/` | 讀取與型別轉換 | 自製 | serde 的 `Deserialize` | 🟢 低 | |
| `config/secrets/` | 加密欄位處理 | 自製 | `secrecy` + AES (`aes-gcm`) | 🟡 中 | 加密格式需保留以兼容既有 config |
| `config/source/file/memory/flag/...` | 檔案/記憶體/CLI flag source | fsnotify | `notify`(file-watch)+ `clap`(flag) | 🟢 低 | |

### 1.2 日誌系統(graphify 顯示這是核心,~80 個節點)

| Go 模組 | 職責 | Go 依賴 | Rust 對應 | 複雜度 | 風險點 |
|---|---|---|---|---|---|
| `logger/` (`Logger` 介面、`Trace/Debug/Info/...`) | 統一日誌介面 | logrus, zap | **`tracing`** + `tracing-subscriber` | 🟡 中 | tracing 是全 Rust 標準;遷移後 API 完全不同 |
| `logger/writer/` | 多輸出(stdout/file/lumberjack) | gopkg.in/natefinch/lumberjack | `tracing-appender`(含 rolling) | 🟢 低 | rolling 策略略有不同 |
| Sanitizer / Sampling / Async layer | 敏感欄位遮罩、取樣、非阻塞輸出 | 自製 | 自寫 `tracing-subscriber::Layer` | 🟠 高 | 全自製 Layer,無現成 crate;**graphify 報告顯示這層做過深度設計**(P0 修過 sampling state bug、Zap FD leak),不能直接抄 |
| `logger/formatter`(顏色/欄位/zero-alloc) | 自製格式器 | 自製 | tracing-subscriber 的 `format::Format` | 🟡 中 | 顏色用 `nu-ansi-term` 或 `colored` |
| Logrus adapter(50+ hooks) | 為相容生態保留 logrus | logrus | **直接放棄**;Rust 不需要 logrus 相容 | 🟢 低 | 切到 tracing 後此模組消失 |

### 1.3 認證 / 授權

| Go 模組 | 職責 | Go 依賴 | Rust 對應 | 複雜度 | 風險點 |
|---|---|---|---|---|---|
| `jwtauth/` | GinJWTMiddleware 移植 | appleboy/gin-jwt | **`jsonwebtoken`** + axum middleware tower layer | 🟡 中 | gin-jwt 的 `Authenticator/Authorizator/PayloadFunc` 鉤子要用 trait 重新組織 |
| `jwtauth/user/` | 從 context 取 user | 自製 | axum extractor (`FromRequestParts`) | 🟢 低 | |
| `casbin/` | Casbin 整合與 enforcer 持有 | casbin/casbin/v3 | **`casbin-rs`** | 🟢 低 | API 幾乎 1:1 |
| `sdk/pkg/casbin` | RBAC 規則載入助手 | gorm-adapter | `casbin-rs` 的 `sqlx-adapter` | 🟢 低 | adapter 不必自寫 |

### 1.4 SDK 容器(`sdk/`)

| Go 模組 | 職責 | Rust 對應 | 複雜度 | 風險點 |
|---|---|---|---|---|
| `sdk/runtime/` (`Runtime`、`Application`) | 全域應用容器、單例 | `OnceCell<Application>` 或 DI 注入(`shaku`) | 🟡 中 | Rust 慣用 DI 不是「全域 singleton」;需重新設計依賴注入點 |
| `sdk/api/` (`Api` 基底、`PageOK/Error/Custum`) | Gin handler 的共用基底 | axum extractor + 自製 `ApiResponse` enum | 🟢 低 | |
| `sdk/antd_api/` | Antd Pro 風格回應格式 | 自製 `AntdResponse` 序列化型別 | 🟢 低 | |
| `sdk/config/` (DBConfig/JWT/SSL/Application/Logger 等型別) | 配置 schema | `serde::Deserialize` struct | 🟢 低 | |
| `sdk/pkg/` | 雜項工具(captcha, cronjob, ws, response, utils) | 詳見下方 | — | 拆分到各對應 crate |
| `sdk/service/` | 服務層基底 | trait + axum state | 🟡 中 | |

### 1.5 SDK 子工具(`sdk/pkg/`)

| Go 子模組 | 職責 | Go 依賴 | Rust 對應 | 複雜度 |
|---|---|---|---|---|
| `sdk/pkg/captcha` | 圖形驗證碼 | mojocn/base64Captcha + golang/freetype | **`captcha`** crate 或自寫(用 `ab_glyph`) | 🟠 高 |
| `sdk/pkg/cronjob` | 定時任務 | robfig/cron | `tokio-cron-scheduler` 或 `apalis` | 🟡 中 |
| `sdk/pkg/ws` | WebSocket 管理(房間、廣播) | gorilla/websocket | `axum::extract::ws` + 自製管理器 | 🟡 中 |
| `sdk/pkg/response` | 回應助手 | gin | axum + serde | 🟢 低 |
| `sdk/pkg/utils` | 雜項(IP / hash / encrypt) | 多種 | `sha2`/`md5`/`hex`/`base64`/`bcrypt` | 🟢 低 |

### 1.6 儲存 / 快取 / 佇列(`storage/`)

| Go 模組 | 職責 | 實作 | Rust 對應 | 複雜度 | 風險點 |
|---|---|---|---|---|---|
| `storage/cache/memory.go` | 記憶體快取(`Cache`、`Memory`) | sync.Map | **`moka`** 或 `dashmap` | 🟢 低 | |
| `storage/cache`(Redis 變體在 sdk/pkg) | Redis 快取 | go-redis/v9 | `redis` crate / `fred` | 🟢 低 | |
| `storage/queue/memory.go` | 記憶體佇列 | channel | `tokio::sync::mpsc` 或 `flume` | 🟢 低 | |
| `storage/queue`(Redis Streams 變體) | 對接 redisqueue fork | go-redis/v9 + redisqueue | `redis` crate XADD/XREADGROUP 自寫 streams 抽象 | 🟡 中 | redisqueue fork 改寫成本見前份評估 |

### 1.7 可觀測性 / 錯誤

| Go 模組 | 職責 | Rust 對應 | 複雜度 |
|---|---|---|---|
| `errors/` (含 protobuf `errors.proto`) | 錯誤碼與 ErrorCoder | `thiserror` + 自製 `ErrorCode` enum;protobuf 用 `prost` | 🟡 中 |
| `observability/audit/` & `observe/audit/` | 審計日誌(graphify 顯示有兩個並存,疑似遷移中) | `tracing` + 自製 audit subscriber | 🟡 中 |
| `response/` & `response/antd/` | 回應型別 | serde struct | 🟢 低 |
| `server/` & `server/listener/` | 自訂 listener(reuseport / ssl) | axum + `hyper` + `socket2`(reuseport)+ `rustls` | 🟡 中 |

### 1.8 工具庫(`tools/`)

| Go 模組 | 職責 | Go 依賴 | Rust 對應 | 複雜度 | 風險點 |
|---|---|---|---|---|---|
| `tools/database/` | DB 配置 + DSN 處理 | gorm | sqlx 或 sea-orm 配置 | 🟢 低 | |
| `tools/gorm/` (`gormlog`, `logger`) | GORM 日誌橋接 | gorm | sea-orm/sqlx + tracing 整合 | 🟡 中 | |
| `tools/language/parser.go` | i18n 解析器 | 自製 | `fluent-rs` 或 `gettext-rs` | 🟡 中 | DSL 不同 |
| `tools/poster/` (`poster.go`, `source.go`) | 圖像合成海報 | image, freetype | `image` + `imageproc` + `ab_glyph` | 🟠 高 | 字型對應、圖層合成 API 完全不同 |
| `tools/search/` (struct-tag DSL: exact/contains/gt/in/order) | gorm 條件 builder | reflection | sea-orm 的 `Condition` builder + 自製 derive macro | 🟠 高 | **graphify 標為獨立 community**;DSL 全自製要實作 procedural macro |
| `tools/transfer/gin.go` | gin 資料轉換助手 | gin | axum extractor 自寫 | 🟢 低 | |
| `tools/utils/excel.go` | Excel 匯入/匯出 | xuri/excelize | `calamine`(讀)+ `rust_xlsxwriter`(寫) | 🟡 中 | excelize 的 styles 對應不同 |
| `tools/utils/grpc_header.go` | gRPC metadata helper | grpc-go | `tonic` metadata | 🟢 低 | |

### 1.9 其他

| Go 模組 | 職責 | Rust 對應 | 複雜度 |
|---|---|---|---|
| `captcha/` (頂層) | 驗證碼整合層 | 同 sdk/pkg/captcha | 🟠 高 |
| `docs/` | 架構/遷移文件 | 翻譯為 Rust 設計文件 | 🟢 低 |

---

## Part 2 — `fork260506-go-admin` 模組對應(應用層)

### 2.1 入口(`cmd/`)

| Go 模組 | 職責 | Go 依賴 | Rust 對應 | 複雜度 |
|---|---|---|---|---|
| `cmd/api/server.go` | 啟動 HTTP server 主流程 | spf13/cobra | **`clap`** + 自寫 startup pipeline | 🟡 中 |
| `cmd/api/jobs.go` | 註冊定時任務 | cronjob | tokio-cron-scheduler | 🟢 低 |
| `cmd/api/other.go` | 其他子命令 | cobra | clap subcommand | 🟢 低 |
| `cmd/app/` | 應用初始化 | 自製 | 改為 main 啟動函式 | 🟢 低 |
| `cmd/config/` | config 子命令 | cobra | clap | 🟢 低 |
| `cmd/migrate/` (含 `migration/` 子目錄) | DB 遷移 | gorm AutoMigrate + 手寫遷移檔 | `sqlx::migrate!` 或 `sea-orm-migration` | 🟡 中 |
| `cmd/version/` | 版本命令 | cobra | clap | 🟢 低 |

### 2.2 業務應用(`app/`)

| Go 模組 | 職責 | 規模 | Rust 對應 | 複雜度 | 風險點 |
|---|---|---|---|---|---|
| `app/admin/apis/` | 約 30 個 API endpoint(SysApi/SysConfig/SysDept/SysDictData/SysDictType/SysJob/SysLoginLog/SysMenu/SysPost/SysRole/SysUser/...) | 大 | axum handler + extractor | 🟡 中 | 純翻譯 |
| `app/admin/models/` | 對應的 GORM models | 大 | sea-orm Entity 或 sqlx struct | 🟡 中 | GORM 軟刪除/audit 欄位需明確處理 |
| `app/admin/service/` | 業務邏輯層 | 大 | trait + impl,axum state 注入 | 🟡 中 | 大量 `Get/GetPage/Insert/Update/Delete` 樣板 |
| `app/admin/service/dto/` | 請求/回應 DTO(超過 10 個 community) | 中 | serde struct + `validator` | 🟢 低 | 純翻譯 |
| `app/admin/middleware/` | 業務中介層 | 小 | tower layer | 🟢 低 | |
| `app/admin/router/` | 路由註冊 | 中 | axum `Router::nest` | 🟢 低 | |
| `app/admin/migration/` | 業務遷移 | 中 | sqlx migrations | 🟡 中 | |
| `app/jobs/` (含 `jobbase.go`, `examples.go`, `httpjob.go`, `execjob.go`) | 定時任務範例與基底 | 小 | tokio-cron-scheduler job | 🟢 低 | |
| `app/other/` | 雜項 | 極小 | — | 🟢 低 | |

### 2.3 共用層(`common/`)

| Go 模組 | 職責 | 規模 | Rust 對應 | 複雜度 | 風險點 |
|---|---|---|---|---|---|
| `common/actions/` (`type.go` 等) | 通用 CRUD action 抽象 | 中 | 自寫 trait `CrudHandler` + axum 路由 helper | 🟠 高 | 大量泛型反射,Rust 要用 trait + macros 重寫 |
| `common/apis/` | API 共用基底 | 中 | axum 共用 extractor / handler | 🟢 低 | |
| `common/database/` (`open.go`, `open_sqlite3.go`) | DB 連線開啟、SQLite 特殊處理 | 小 | `sqlx::PgPool/MySqlPool/SqlitePool` | 🟢 低 | CGO sqlite 在 Rust 沒有(`rusqlite`/`libsqlite3-sys` 內建) |
| `common/dto/` (`Pagination`, `ObjectById`, `GeneralDelDto/GetDto`) | 通用 DTO | 小 | serde struct | 🟢 低 | |
| `common/file_store/` `interface.go` | 檔案儲存介面 (`ClientOption`, `FileStoreType`) | 小 | trait `FileStore` | 🟢 低 | |
| `common/file_store/oss.go`(阿里雲) | OSS client 包裝 | 小 | **無 Rust SDK,需自寫 REST**(用 `reqwest` + 阿里雲簽名 v4) | 🔴 極高 | 簽名與 multipart upload 要 100% 自寫 |
| `common/file_store/obs.go`(華為雲) | OBS client 包裝 | 小 | **無 Rust SDK,需自寫 REST**(類 S3 簽名) | 🔴 極高 | 同上 |
| `common/file_store/kodo.go`(七牛) | Qiniu client 包裝 | 小 | 社群 crate `qiniu-rs`(完整度可,但要驗測) | 🟠 高 | 社群品質風險 |
| `common/global/` (`adm.go`, `logo.go`, `topic.go`) | 全域變數 | 極小 | `OnceCell` 或常數 | 🟢 低 | |
| `common/middleware/auth.go` | JWT auth | 小 | tower layer + jsonwebtoken | 🟡 中 | |
| `common/middleware/customerror.go` | 錯誤統一處理 | 小 | axum `IntoResponse` + 自製 Error type | 🟢 低 | |
| `common/middleware/db.go` | DB context 注入 | 小 | axum `State` extractor | 🟢 低 | |
| `common/middleware/demo.go` | demo 模式攔截寫入 | 小 | tower layer | 🟢 低 | |
| `common/middleware/handler/` | middleware 子助手 | 小 | tower 子模組 | 🟢 低 | |
| `common/middleware/header.go` | header 解析 | 小 | axum extractor | 🟢 低 | |
| `common/middleware/init.go` | 中介層註冊 | 小 | `Router::layer` 鏈 | 🟢 低 | |
| `common/middleware/logger.go` | 請求日誌 | 小 | `tower-http::trace` | 🟢 低 | |
| `common/middleware/permission.go` | Casbin 權限檢查 | 小 | tower layer + casbin-rs | 🟡 中 | |
| `common/middleware/request_id.go` | request id | 小 | `tower-http::request_id` | 🟢 低 | |
| `common/middleware/sentinel.go` | **Sentinel 流量控制** | 小 | **無 Rust 對應**;需用 `governor`(rate limit)+ 自製 circuit breaker | 🟠 高 | Sentinel 的規則語意(系統指標/併發/慢調用比例)Rust 端要全部重新設計 |
| `common/middleware/settings.go` | 設定注入 | 小 | axum `State` | 🟢 低 | |
| `common/middleware/trace.go` | tracing | 小 | `tracing` + `opentelemetry-otlp` | 🟢 低 | |
| `common/models/` (`Model`/`BaseModel`、`ControlBy` audit 欄位) | 通用模型基底 | 小 | sea-orm 的 ActiveModel + 自製 trait | 🟡 中 | |
| `common/response/` | 回應助手 | 小 | axum `IntoResponse` impl | 🟢 低 | |
| `common/service/` | 服務基底 | 小 | trait | 🟢 低 | |
| `common/storage/initialize.go` | 儲存系統初始化 | 小 | startup pipeline | 🟢 低 | |

### 2.4 模板與靜態資源

| Go 模組 | 職責 | Rust 對應 | 複雜度 |
|---|---|---|---|
| `template/v4/` | 程式碼產生器模板(.go.template) | 改寫成 Rust 模板(`askama`/`tera` + Rust syntax) | 🟠 高 |
| `static/form-generator/`(Vue 編譯產物) | 前端 bundle | 不動,直接 serve | 🟢 低 |
| `static/uploadfile/` | 範例上傳 | 不動 | 🟢 低 |
| `docs/admin/` | Swagger 自動文件(swaggo) | **`utoipa`**(Rust OpenAPI) | 🟡 中 |

---

## Part 3 — 跨層共享依賴對應總表

| Go 依賴 | 用途 | Rust 對應 | 成熟度 | 備註 |
|---|---|---|---|---|
| gin-gonic/gin | HTTP framework | **axum** | ✅ 成熟 | 同屬 tower 生態,中介層豐富 |
| go-admin-team/gorm-adapter | Casbin GORM adapter | casbin-rs `sqlx-adapter` | ✅ 成熟 | |
| go-admin-team/redis-watcher | Casbin Redis 通知 | casbin-rs `redis-watcher` | ✅ 成熟 | |
| gorm.io/gorm | ORM | **sea-orm** / `sqlx` | ✅ 成熟 | sea-orm 較貼近 ActiveRecord;sqlx 更輕 |
| casbin/casbin/v2,v3 | RBAC | **casbin-rs** | ✅ 成熟 | |
| redis/go-redis/v9 | Redis | **`redis`** crate / `fred` | ✅ 成熟 | |
| golang-jwt/jwt/v5 | JWT | **`jsonwebtoken`** | ✅ 成熟 | |
| spf13/cobra | CLI | **`clap`** | ✅ 成熟 | |
| spf13/viper | Config | **`figment`** / `config` | ✅ 成熟 | |
| go-playground/validator | 驗證 | **`validator`** | ✅ 成熟 | |
| bytedance/go-tagexpr/v2 | tag DSL 驗證 | **無等價** | ❌ 缺口 | DSL 規則需翻譯成 validator + 自製 derive |
| alibaba/sentinel-golang | 流量/熔斷 | **無等價** | ❌ 缺口 | 用 `governor` + 自製 circuit breaker |
| alibaba/sentinel-golang/.../gin | Gin 整合 | — | ❌ 缺口 | 自寫 tower layer |
| aliyun/aliyun-oss-go-sdk | 阿里雲 OSS | **無官方 SDK** | ❌ 缺口 | 需自寫 |
| huaweicloud/.../go-obs | 華為雲 OBS | **無官方 SDK** | ❌ 缺口 | 需自寫 |
| qiniu/api.v7(實際是 kodo SDK) | 七牛 | qiniu-rs(社群) | ⚠️ 部分 | 完整度需驗 |
| chanxuehong/wechat | 微信 | 社群零星 | ⚠️ 部分 | 視業務需求 |
| robfig/cron / cronjob | 定時 | `tokio-cron-scheduler` / `apalis` | ✅ 成熟 | |
| gorilla/websocket | WS | `axum::extract::ws` / `tokio-tungstenite` | ✅ 成熟 | |
| xuri/excelize | Excel | `calamine`(讀)+ `rust_xlsxwriter`(寫) | ✅ 成熟 | |
| swaggo/swag | Swagger 生成 | **`utoipa`** | ✅ 成熟 | |
| google/uuid | UUID | **`uuid`** | ✅ 成熟 | |
| pkg/errors | 錯誤包裝 | `anyhow` + `thiserror` | ✅ 成熟 | |
| google/freetype | 字型(captcha/poster) | `ab_glyph` / `rusttype` | ✅ 成熟 | API 完全不同 |
| mojocn/base64Captcha | 驗證碼 | `captcha` crate / 自寫 | ⚠️ 部分 | |
| mssola/user_agent | UA 解析 | `ua_parser` / `woothee` | ✅ 成熟 | |
| prometheus/client_golang | metrics | **`prometheus`** / `metrics` | ✅ 成熟 | |
| opentracing/opentracing-go | 分散式追蹤 | **`opentelemetry`**(直接升級) | ✅ 成熟 | opentracing 已 deprecated |
| logrus / zap | 日誌 | **`tracing`** | ✅ 成熟 | |
| fsnotify/fsnotify | 檔案監聽 | `notify` | ✅ 成熟 | |
| BurntSushi/toml | TOML | `toml` | ✅ 成熟 | |
| ghodss/yaml + bitly/go-simplejson | YAML + JSON | `serde_yaml` + `serde_json` | ✅ 成熟 | |
| dario.cat/mergo | struct merge | `serde` + 自製 merge | ⚠️ 部分 | 通常結合 figment 解 |
| shirou/gopsutil(server monitor) | 系統指標 | **`sysinfo`** | ✅ 成熟 | |

---

## Part 4 — 改寫複雜度熱點(必看)

### 🔴 極高(直接卡住改寫進度)

1. **阿里雲 OSS SDK 自製** — 簽名、multipart、STS、域管理。約 0.5–1 人月。
2. **華為雲 OBS SDK 自製** — 同上,類 S3 但有差異。約 0.5 人月。
3. **`common/actions` 通用 CRUD 抽象** — Go 用反射 + interface 實作的「萬用 controller」,在 Rust 要用 trait + macros 重寫,且型別系統不容讓你抄一樣的形狀。約 0.5 人月。

### 🟠 高(技術可行但工時大)

4. **Sentinel 替代** — `tower::limit` + `governor` + 自製 circuit breaker。語意對齊驗證 0.5 人月。
5. **Logger 三層 (Sanitizer + Sampling + Async)** — graphify 顯示這層做過深度設計與 P0 修復,要在 `tracing-subscriber::Layer` 下重做。0.5–1 人月。
6. **`tools/search` struct-tag DSL** — 自製 procedural macro + sea-orm Condition builder。0.5 人月。
7. **`tools/poster` 海報生成** — image API 不同,字型/合成需重寫。1–2 週。
8. **驗證碼 (`captcha`)** — `captcha` crate 不一定符合既有 base64Captcha 的格式;若需相容 1 週。
9. **`bytedance/go-tagexpr` 規則翻譯** — 把所有 `vd:"..."` tag 改成 validator 對應規則。視規模 1–2 週。
10. **七牛 `kodo` 整合** — 社群 SDK 可能要 patch,1–2 週緩衝。
11. **`template/v4` 程式碼產生器** — 要改寫所有 .go.template 為 Rust 對應(askama/tera + 自寫 codegen pipeline)。0.5–1 人月。

### 🟡 中(常規重構,但量大)

- 所有 `app/admin/apis` (~30 endpoint)+ `service` + `models` + `dto` 翻譯到 axum + sea-orm。
- DB migration 改用 `sqlx::migrate!` 或 `sea-orm-migration`,需逐檔對齊。
- JWT middleware 用 tower layer 重寫,鉤子要重新設計成 trait。
- `errors/` 含 protobuf 定義,需用 `prost` 重生並對齊。
- WebSocket 房間/廣播管理器自寫(成熟但無 1:1)。

### 🟢 低(直接翻譯)

- 大量 DTO (~20+ community 都是 DTO)、回應助手、Pagination、ObjectById、common/global。
- 中介層多數(request_id、demo、logger、settings、trace、header、handler)。
- 雜項工具 (`utils/` 大半:hash/encrypt/IP/string)。
- 配置編解碼 (json/yaml/toml/xml)。

---

## Part 5 — 推薦改寫順序

依據「依賴鏈由下往上」+「先解掉風險最大的」:

1. **PoC 階段(1 個月)**:挑一個垂直切片(例如 SysUser 從 model → service → api → JWT auth),用 Rust + axum + sea-orm + casbin-rs 全跑通,驗證:
   - sea-orm 與 GORM 的 audit 欄位/軟刪除等慣例是否能 1:1 對齊
   - JWT middleware 的鉤子重設計可行性
   - `tracing` 三層(sanitizer/sampling/async)PoC
   - 確認阿里雲 OSS / 華為雲 OBS 不在這一切片(避免一開始就卡破口)

2. **Phase 1:框架層下半部**(2 人月)
   - logger 三層、config 系統、errors、storage/cache、storage/queue(memory)
   - jwtauth、casbin 整合、sdk/runtime、sdk/api、response

3. **Phase 2:框架層上半部 + 工具庫**(1.5 人月)
   - tools/search DSL macro、tools/database、tools/gorm logger 橋接、tools/utils/excel、cronjob、ws
   - **此時必須先決定 Sentinel 替代方案**,否則 phase 3 卡住

4. **Phase 3:應用層 + 雲 SDK**(2.5 人月)
   - cmd 入口、common/* 共用層、middleware
   - 阿里雲 OSS / 華為雲 OBS 自寫 SDK(可平行)
   - sentinel 替代落地

5. **Phase 4:業務模組翻譯**(2 人月)
   - app/admin/* 全部 endpoint(~30 個)、service、models、migration
   - jobs

6. **Phase 5:整合測試 + 過渡期雙跑**(1–2 人月)
   - 與現有 Go 版本流量對打
   - performance 與 memory 比對
   - 灰度切換

**總計:約 9–11 人月(單人估)**,團隊規模 2–3 人可壓到 4–6 個月,但 PoC 階段沒法平行。

---

## Part 6 — 與 SpecKit Constitution 的衝突點

七個 repo 剛 ratify 的 constitution(`v1.0.0`)有兩條原則直接被改寫違反:

1. **go-admin-core Principle II — Backward compatibility within MAJOR via zero-cost shims**
   改寫成 Rust 等於 MAJOR break,且不再有任何 shim 能保兼容 Go 用戶。這條原則必須先廢止或明訂 「Rust 重寫屬 v2.0.0 重大版本,不適用此原則」。

2. **共通 Principle II — Fork hygiene + upstream traceability**
   改寫後永遠脫離上游,以後上游 PR 都得「翻譯」而非 cherry-pick,Sync Impact 報告無法產生。需評估「上游是否仍活躍」— 若 go-admin / casbin 上游仍在更新,改寫後同步成本可能比改寫本身還大。

**建議**:在啟動前先過 constitution amendment,把這兩條原則的 scope 明確排除「Rust port 子專案」,否則 PoC 階段就會跟 SpecKit 規範打架。
