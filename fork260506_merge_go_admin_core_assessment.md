# go-admin × go-admin-core 合併成單一專案的工作評估

評估日期:2026-05-07
範圍:`fork260506-go-admin`(應用層,18,204 LOC)+ `fork260506-go-admin-core`(框架 SDK,17,884 LOC)

## 0. 先釐清動機(必答)

合併本身不是純技術問題,合併會付出固定代價,做之前要先確認動機:

| 動機 | 是否合理? | 註 |
|---|---|---|
| 兩個 repo 改一個功能要 cross-PR,流程繁瑣 | ✅ 強動機 | 合併直接消除 |
| 版本對齊(go-admin 引 core 用 pseudo-version)很煩 | ✅ 強動機 | 目前 go-admin 還在 require `core/sdk` 子 module,代表已經有版本錯配 |
| 想去掉「core 對外可被 import」的承諾,讓內部修改更自由 | ✅ 看狀況 | 但 core README 仍宣告 `go get -u .../go-admin-core`,合併等於明確放棄 SDK 角色 |
| 想簡化 fork 維護(同步上游) | ⚠️ 反效果 | 上游本來就是兩個 repo,合併後 cherry-pick 變成「翻譯成新結構」,**反而更難** |
| CI/CD 簡化 | ⚠️ 邊際收益 | core 目前無 CI,合併後是「往 go-admin 套」,工作量在那邊 |

**如果只是因為「兩個 repo 看起來礙眼」,先停下** — 合併不是免費的,代價見 §6。

## 1. 既有耦合面快照(probe 結果)

| 事實 | 觀察 |
|---|---|
| `go-admin-core` 已是**單 module**(graphify v1.6 紀錄「4 go.mod → 1」) | 但 `go-admin` 的 `go.mod` 仍同時 require `core` + `core/sdk`(舊多 module 路徑)— **版本錯配,合併前要先升級** |
| `go-admin` 對 core 的 unique import 路徑:**27 條** | 耦合中等,集中在 `sdk/`、`logger/`、`storage/`、`config/`、`tools/`、`jwtauth/`、`captcha/`、`casbin/` |
| `go-admin-core` import 中**沒有** `redis-watcher` / `redisqueue` | 這兩個 fork 跟合併**無關**(目前是閒置的) |
| `gorm-adapter` 只被 `core` import,`go-admin` 沒直接用 | 合併要不要順手吞掉這個 fork,是**獨立決策** |
| `go-admin-core` 沒有 `.github/workflows/`、沒有 `Makefile` | 合併後 CI 完全靠 `go-admin` 那 7 個 workflow |
| 兩 repo 各自有 `graphify-out/GRAPH_REPORT.md` 與剛 ratify 的 SpecKit constitution v1.0.0 | 合併後**兩份報告 + 兩份 constitution** 都要重新整併 |
| `go-admin/go.mod` 留有**已註解**的 `replace` 指令(指向 `../go-admin-core`)| 證據:開發者過去就在本地以工作區方式併行修改兩 repo |

## 2. 合併形態三選一

| 方案 | 結構 | 解決什麼 | 不解決什麼 | 工時 |
|---|---|---|---|---|
| **A. Go workspace** (`go.work`) | 兩 repo 維持獨立,根目錄加 `go.work` 把兩個指向本地 | 改善「同時改兩 repo 開發體驗」 | 仍是兩 repo,版本/CI/issue 仍分開 | **0.5 週** |
| **B. Monorepo + 雙 module** | 把 `core/` 移進 `go-admin/` 變成子目錄,各自留 `go.mod`,雙 release tag | 共享 issue / PR / CI,但仍可單獨發版 core | tooling 較複雜(monorepo go module 規則、tag 命名) | **1–2 週** |
| **C. 完全合併成單 module** | `core` 整個併入 `go-admin/internal/core/` 或 `go-admin/pkg/core/`,單 `go.mod` | 真正一個專案,版本完全綁一起 | **正式放棄 core 對外 SDK 角色**;上游 cherry-pick 變翻譯 | **2–4 週** |

**推薦**:
- 短期想止血開發痛點 → **方案 A**,不可逆性低
- 確定 go-admin-core 已沒有外部使用者(只給 go-admin 用)→ **方案 C**,徹底簡化
- 中間立場 → **方案 B**

以下工作清單按 **方案 C** 展開(其他方案是 C 的子集)。

## 3. 工作清單(方案 C:完全合併)

### 3.1 前置(P0,必須先做)

- [ ] **升級 `go-admin` 到 core v1.6 結構**
  - 移除 `go.mod` 對 `github.com/go-admin-team/go-admin-core/sdk` 的 require
  - 把所有 import `.../go-admin-core/sdk/...` 改成 `.../go-admin-core/sdk/...`(實際 path 不變但版本來源變)或用 v1.6 的 compatibility shim
  - **不先做這一步,合併後 import path 改寫會跟版本升級的 import 改寫疊在一起,review 不可讀**
- [ ] 確認沒有外部下游使用者:`fork260506-go-admin-core` 是 fork,本身對外無 release,但 README 仍宣告 `go get`。發公告或刪除 SDK 字樣。
- [ ] 在合併前各自跑一次 `go test ./...` + `graphify update .` 留下基準

### 3.2 SpecKit Constitution 整併(P0,governance gate)

兩 repo 剛 ratify 的 constitution v1.0.0 在合併後**直接衝突**:

| Principle | go-admin (應用層) | go-admin-core (框架層) | 衝突 |
|---|---|---|---|
| I | fork discipline | core boundary: infra-only, no business logic | core 併進 go-admin 的 `internal/` 後,「對外 SDK 邊界」這條原則失效 |
| II | API/permission contract stability | Backward compatibility within MAJOR via zero-cost shims | core 不再對外發版,「shim 兼容」原則失效 |
| III | mandatory tests for auth/persistence | test-first + race-verified + benchmark-bound | 兩條合併成一條 |
| IV | spec-driven workflow | composable adapters | 概念無衝突但要重新表述 |
| V | observability | observability-by-default with sanitization/sampling | 合併版本應採用 core 的更嚴格版 |

工作:
- [ ] 啟動 `/speckit.constitution` amendment 流程,產出合併後的 v2.0.0
- [ ] 寫 Sync Impact Report 標記哪些原則退場、哪些升級
- [ ] 對齊 `.specify/templates/{plan,tasks,spec}.md` 的 Constitution Check 區塊
- [ ] 兩 repo 的 `.specify/memory/constitution.md` 收斂成單一檔

### 3.3 Git History 合併

- [ ] 決定 history 策略:
  - **`git subtree add --prefix=core ../fork260506-go-admin-core main`**(推薦)— 保留 core 完整 history,在 go-admin 中可見
  - `git read-tree --prefix=core` + `filter-branch` — 較精細但風險高
  - 不保留 history,只移檔 — 最簡單但 `git blame` 斷掉
- [ ] 在合併 commit 中明確標記:`merge: integrate go-admin-core as core/`,並在 commit body 寫上來源 SHA
- [ ] 處理 `go-admin-core` 的 `.git`、`graphify-out/cache/`、`.specify/` 等不該帶進來的目錄

### 3.4 目錄結構決策

| 選項 | 路徑 | 對外可見? | 適用情境 |
|---|---|---|---|
| `core/` (root) | `go-admin/core/...` | 是,可被 import | 仍想保留「未來可拆出去」彈性 |
| `pkg/core/` | `go-admin/pkg/core/...` | 是 | Go 慣例 |
| `internal/core/` | `go-admin/internal/core/...` | **否,Go 編譯器強制不可被外部 import** | 確定不再對外時最強保證 |

**推薦 `internal/core/`** — 配合「方案 C 放棄 SDK 角色」的決策,讓編譯器幫你守邊界。

### 3.5 Module Path 改寫

- [ ] 全 repo 替換 27 條 unique import paths:
  ```
  github.com/go-admin-team/go-admin-core/...   →   go-admin/internal/core/...
  ```
- [ ] 用 `gofmt -r` 或 `goimports -local` 一次處理,**不要手改**
- [ ] 留意 indirect import:`go-admin-core/plugins/logger/zap` 等出現在 indirect block,合併後變內部
- [ ] 跑 `go mod tidy` 收斂 `go.mod` / `go.sum`

### 3.6 內部依賴結構整理

合併後重新評估:
- [ ] **`sdk/runtime/` 全域 Application 容器** — 原本是「core 提供、app 消費」的單例,合併後有沒有更好的 DI 寫法?(可選 refactor)
- [ ] **`sdk/api/` vs `common/apis/`** — 兩 repo 各有一份「API 共用基底」,合併後該整併
- [ ] **`response/` vs `common/response/`** — 同上,兩份重複
- [ ] **`config/` vs `cmd/config/`** — config 抽象在 core,config 子命令在 app,合併後關係更直接
- [ ] **error 型別** — `errors/` 在 core,`common/middleware/customerror.go` 在 app,合併後可以用單一錯誤體系
- [ ] **`tools/` 的去留** — `tools/poster`、`tools/search`、`tools/transfer/gin.go` 是 core 提供但**只有 go-admin 在用**,合併後可以直接放進 `app/` 對應位置

### 3.7 CI / CD 整併

- [ ] 把 `go-admin/.github/workflows/` 的 7 個 workflow 適配新結構:
  - `build.yml`、`go.yml`:增加 `internal/core/...` 的 build/test 範圍
  - `codeql-analysis.yml`:擴大掃描範圍
  - `issue-check-inactive.yml`、`issue-labeled.yml`、`issue-close-require.yml`:標籤體系要含 core
  - `mirror.yaml`:鏡像目標確認
- [ ] core 的單元測試與 benchmark(README 提到 35 unit tests + 30+ benchmarks)接到 go-admin CI
- [ ] 整併後跑一次完整 CI,確保通過

### 3.8 文件 / README

- [ ] **README**:兩 repo 各有中英版本(共 4 份),合併後一份主 README,中文移到 `README.zh-CN.md`
- [ ] **`core/docs/architecture/logging-architecture.md`** + PDF:整套日誌設計文件保留
- [ ] **`core/docs/migration/`**:v1.6 遷移文件保留作為歷史紀錄
- [ ] go-admin 自身的 `docs/admin/` (Swagger) 不變
- [ ] 把 core README 的「`go get -u .../go-admin-core`」字樣全部移除,改成「core 為內部框架,不對外發版」

### 3.9 graphify 重跑

- [ ] 合併後從 go-admin root 跑 `graphify .`,產生整體圖
- [ ] 兩 repo 各自的 `graphify-out/` 要刪除(或保留為歷史快照,但 root CLAUDE.md 要更新只指向新報告)
- [ ] 預期合併後 nodes ≈ 3000+, edges ≈ 8500+,community 數量上升;成本約 30~40k tokens

### 3.10 釋出與切換

- [ ] 合併版打 tag `v2.0.0`(MAJOR break)
- [ ] go-admin / go-admin-core 兩個 fork 仍保留,新 issue/PR 統一導到合併後的 repo,或廢止 core repo(archive)
- [ ] 同步在 `fork260506.md` / `fork260506_relationship.md` / `fork260506_update.md` 紀錄合併事件

### 3.11 順手評估的副題(可不做)

- [ ] **gorm-adapter fork 是否一起併入?** — 只 core 用、目前是獨立 fork。要不要併進新 repo 的 `internal/casbin-adapter/`?或回到 casbin 上游版?
- [ ] **redis-watcher / redisqueue fork 留著嗎?** — 兩個都沒被任何 repo 引用。合併工作會順便暴露這件事:它們可能是死資產,可以 archive。
- [ ] **go-admin-doc 與 go-admin-ui 與合併後的 repo 關係不變**(本來就不是 Go)— 但要確認 doc 的 navigation 連結還能指對。

## 4. 推薦執行順序

```
PoC ───▶ 升級 ───▶ Constitution ───▶ 合併 ───▶ 整併 ───▶ 釋出
 1d       3d         2d              3–5d      3–5d     1d
```

| 步驟 | 內容 | 工時 |
|---|---|---|
| **1. PoC**(可省) | 在 sandbox 用 `go.work` 試方案 A,確認可行才走方案 C | 1 天 |
| **2. 升級 go-admin 引用 core v1.6** | 消掉 `core/sdk` 子 module require,跑通 `go test` | 2–3 天 |
| **3. SpecKit constitution amendment** | 兩 repo 各自的 v1.0.0 整併成 v2.0.0 草案,review | 1–2 天 |
| **4. Git history 合併 + import 改寫** | subtree add、`internal/core/` 落位、import 全替換、`go mod tidy`、CI 跑通 | 3–5 天 |
| **5. 結構整併** | sdk/api 跟 common/apis 合一、response 合一、文件整併、graphify 重跑 | 3–5 天 |
| **6. 釋出 v2.0.0** | tag、changelog、舊 repo archive | 1 天 |
| **總計** | | **2–3 週**(單人) |

## 5. 風險清單

### 🔴 高風險
- **constitution 衝突** — 必須先過 amendment,否則合併過程中 SpecKit gate 會擋
- **fork 同步策略改變** — 上游兩個 repo,合併後 cherry-pick 變人工分流;若上游仍活躍,**長期成本可能比合併本身高**
- **`go-admin` 用 v1.5 但 core 已 v1.6** — 合併前必須先升級,否則 import path 改寫會跟版本升級疊在一起

### 🟠 中風險
- **`sdk/runtime/Application` 全域單例** — 27 條 import 都依賴它,合併後若同時做 DI 重構,影響範圍大;**先合併,別順手 refactor**
- **CI 擴張後執行時間** — core 有 30+ benchmark,接進 go-admin CI 後 PR 跑 CI 時間延長,可能要分 stage
- **graphify token 成本** — 重跑整體圖一次 30~40k tokens

### 🟢 低風險
- 下游使用者破壞:fork 本身不對外,實際無下游
- redis-watcher / redisqueue / gorm-adapter:不在合併範圍,不受影響

## 6. 做與不做的取捨

**做(方案 C)的好處**:
- 一次 PR 可改完應用層 + 框架層
- 版本錯配問題消失(不再有 `core` + `core/sdk` 的雙 require)
- core 對外 SDK 角色取消,內部 refactor 不再受「不能 break SDK」綁手綁腳
- 兩 repo 的 graphify、constitution、CI 收斂成一份

**做的代價**:
- 2–3 週工時(單人,且 PoC 不能省)
- 上游 sync 變成翻譯,長期成本不可逆
- core 文件中強調的「45x async / 29x sampling boost」、「Logrus 50+ hooks」等對外賣點失去意義
- SpecKit constitution v1.0.0 才剛 ratify,馬上要做 v2.0.0 amendment(governance overhead)

**不做(維持兩 repo)的好處**:
- 保留「core 可獨立發版/重用」的選項
- 保留與上游 cherry-pick 的能力
- 不需要 constitution amendment

**不做的代價**:
- 同時改兩 repo 永遠是 cross-PR
- 版本錯配問題還會繼續出現
- 兩份 CI、兩份 constitution、兩份 graphify 持續維護

## 7. 一句話建議

如果**已確認** `fork260506-go-admin-core` 不對外發版、也沒有其他內部應用 import — **走方案 C,2–3 週可收**。
如果還沒確認、或上游兩個 repo 仍頻繁更新 —— **先走方案 A(`go.work`)**,把開發體驗止血,觀察 1–2 個月再決定是否升 C。
