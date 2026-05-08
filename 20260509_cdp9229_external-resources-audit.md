# fork260506-go-admin-ui 外部資源稽核(CDP:9229 抓取)

> **日期**:2026-05-09
> **語言**:zh-TW
> **方法**:CDP `:9229` 訂閱 `Network.requestWillBeSent` / `Network.responseReceived` / `Network.loadingFailed` / `Network.webSocketCreated` 事件,從 `http://127.0.0.1:8080/`(自動 redirect 到 `#/login?redirect=/dashboard`)走完登入流程到 `#/dashboard` 完全載入,過濾 `URL.hostname !== "127.0.0.1"` 的請求。
> **CDP 操作技法**:見 [`20260509_cdp9229_debug.md`](20260509_cdp9229_debug.md) §10.1.3 Network domain event capture。
> **不包含**:`localhost:8000/api/v1/*` 後端 API(同機 docker stack 內部,雖字面非 127.0.0.1 但屬本地)。

---

## 0. TL;DR

login → dashboard 全程的「真實外部請求」共 **3 個 host、4 條 unique URL**:

| Host | 用途 | 狀態 |
|---|---|---|
| `doc-image.zhangwj.com` | 系統 logo 圖 | **失敗** `ERR_CERT_DATE_INVALID`(憑證過期)|
| `wpimg.wallstcn.com` | vue-element-admin 模板殘留的 demo avatar | 200 OK |
| `hm.baidu.com` | 百度統計埋點(`hm.js` + `hm.gif`)| 部分 200、部分 `ERR_ABORTED`(被 client 攔)|

Dev mode 下這些**不影響功能**,但牽涉:離線可用性、隱私、視覺破圖。

---

## 1. 抓到的清單

### 1.1 `doc-image.zhangwj.com`(1 unique URL)

```
FAIL [net::ERR_CERT_DATE_INVALID] | Image |
  https://doc-image.zhangwj.com/img/go-admin.png
```

- **載入時機**:login 頁(`#/login`)即觸發
- **觸發點**:`/api/v1/app-config` 回傳的 `sys_app_logo` 欄位指向此 URL,前端在 `<img :src="sysInfo.sys_app_logo">` 渲染
- **問題**:此 domain 的 TLS 憑證已過期(屬作者 `lwnmengjing` 個人 CDN),browser 拒絕載入 → 畫面顯示破圖 placeholder
- **影響範圍**:dashboard 的 sidebar logo 區、login 左側 logo
- **修法**:
  - **A 短期**:替成 local asset。把 `assets/login.png` 或仿製一張 logo 放 `public/logo.png`,然後改 `app-config` 的回傳邏輯(在 `fork260506-go-admin/` 的 `app-config` handler 改)指向 `/logo.png`
  - **B 折衷**:讓前端在 `sys_app_logo` 載入失敗時 fallback 到 default — `<img :src="logo" @error="logo='/default-logo.png'">`
  - **C 不修**:dev 用,接受破圖

### 1.2 `wpimg.wallstcn.com`(1 unique URL)

```
status=200 | Image |
  https://wpimg.wallstcn.com/f778738c-e4f8-4870-b634-56703b4acafe.gif?imageView2/1/w/80/h/80
```

- **載入時機**:登入後 `/api/v1/getinfo` 回傳後立即載入
- **觸發點**:`getinfo` 回傳 `data.avatar` 寫死這串 URL → vuex `user/SET_AVATAR` 設定 → navbar 頭像 `<img :src="user.avatar">`
- **背景**:這是 [PanJiaChen/vue-element-admin](https://github.com/PanJiaChen/vue-element-admin) 的 demo 用 avatar(七牛雲 CDN),fork 沒換成自家後端的真實頭像
- **後端 source**:`fork260506-go-admin/app/admin/apis/sys_user.go` 或對應 `getinfo` handler 內的 user mock data
- **影響範圍**:navbar 右上角頭像 + sidebar collapse 圖示
- **修法**:
  - **A**:後端把 default avatar 換成 local resource(`/avatar.png`)或從 user record 真實讀
  - **B**:前端在 `SET_AVATAR` mutation 加判斷,外部 URL fallback 為內建 SVG icon
  - **C 不修**:dev 用,wpimg.wallstcn.com 是大廠 CDN 不太會掛,但**有隱私顧慮**(每次 user 開頁都會 ping 一個外部圖)

### 1.3 `hm.baidu.com`(2 unique URLs,4 次 request)

```
status=200       | Script |
  https://hm.baidu.com/hm.js?1d2d61263f13e4b288c8da19ad3ff56d

status=200       | Image  |
  https://hm.baidu.com/hm.gif?...&u=http%3A%2F%2F127.0.0.1%3A8080%2F%23%2Flogin...
FAIL ERR_ABORTED | Image  |
  https://hm.baidu.com/hm.gif?...&u=http%3A%2F%2F127.0.0.1%3A8080%2F%23%2Flogin...
```

- **載入時機**:每次 page load 都觸發(包括 `#/login` 和 `#/dashboard`)
- **觸發點**:`public/index.html` 或某個 vendor file 內嵌入百度統計埋點 snippet(`hm.js` 載入後自動發 `hm.gif` tracking pixel)
- **百度統計站點 ID**:`1d2d61263f13e4b288c8da19ad3ff56d`(query string 第一段)
- **上報內容**:當前 page URL(完整,含 hash),含 `127.0.0.1:8080/#/login?redirect=/dashboard` 這種 dev URL — 實質上把 dev 行為上報給百度
- **隱私問題**:**最值得處理的一條**。即使在台灣,埋點也會發一條到中國伺服器,而且把每個 dev 的 SPA 路由跳轉都上報。Browser 的廣告攔截器會擋部分 `hm.gif`(看到的 `ERR_ABORTED` 就是被擋的)
- **修法**:
  - **A 推薦**:全域移除。grep `fork260506-go-admin-ui/public/index.html` 與 `src/` 內所有 `hm.baidu.com` 或 `hm.js` 引用,整段砍掉(通常是 `<script>` 標籤或 `_hmt` 物件初始化)
  - **B**:用環境變量條件 inject — `if (process.env.NODE_ENV === 'production') {...}`,但這個 fork 是 dev/internal 用,production 也不應該開
  - **C 不修**:接受隱私洩漏

### 1.4 WebSocket 外部連線

```
(none)
```

→ entry 004(`vue.config.js` `webSocketURL: 'auto://0.0.0.0:0/ws'`)修好後,HMR ws 走 `ws://127.0.0.1:8080/ws`。沒有任何外部 ws。

---

## 2. 統計

| 指標 | 值 |
|---|---|
| 全程 tracked HTTP 請求 | 22 |
| 排除 127.0.0.1 後 | 15 |
| 排除 localhost(後端 API)後 | 7 |
| Unique 外部 URL | 4(1 個是同 query string 不同 nonce 的 `hm.gif`,實質 3 條 endpoint) |
| Unique 外部 host | 3 |
| 失敗請求 | 2(`doc-image` 憑證過期、`hm.gif` 被攔)|

---

## 3. 建議優先序

| 優先 | 項目 | 工時 | 影響 |
|---|---|---|---|
| 🔴 高 | 移除 `hm.baidu.com` 埋點 | 5–10 min | 隱私(每次 dev 跳路由都上報中國伺服器) |
| 🟡 中 | 替換 `doc-image.zhangwj.com` logo | 15 min(含 backend `app-config` 改 + asset) | 視覺破圖,當前 dev 看到斷掉的 placeholder |
| 🟢 低 | 替換 `wpimg.wallstcn.com` avatar | 10 min(看選擇 backend 改或前端 fallback)| 隱私 + 離線可用性,視覺上 200 OK 不易察覺 |

---

## 4. 修訂紀錄

| 日期 | 修改 |
|---|---|
| 2026-05-09 | 初版,CDP:9229 掃描 login → dashboard 全程,記錄 3 host / 4 unique URL |
