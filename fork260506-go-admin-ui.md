# fork260506-go-admin-ui: Workspace Patch Log

> Companion to [SUBREPOS.md](SUBREPOS.md). Per SUBREPOS.md **Rule 1** sub-repo
> changes never enter this workspace's git history, and per **Rule 3** the
> sub-repo's working tree may be reverted at any time. This file is the
> durable memory that lets us **re-apply** active patches and **understand
> why** each one exists.
>
> Sub-repo upstream remote: see `git -C fork260506-go-admin-ui remote -v`.
> Sub-repo branch in scope: typically `main`.

## Patches index

**Single source of truth for each patch's lifecycle (Fixed upstream?) and apply-state (Applied on disk?).**
On a fresh session — or after reverting the sub-repo — scan for any item where **both boxes are unticked**; those are the patches that need to be re-applied before bringing up the stack.

- **001** — Disable `<vue-particles>` in `views/login/index.vue` (Vue 3 migration leftover)
  - Fixed upstream? [ ]
  - Applied on disk? [x]
- **002** — `permission.js`: replace `router.addRoutes` with `router.addRoute` (Vue Router 4 API change)
  - Fixed upstream? [ ]
  - Applied on disk? [x]
- **003** — `store/modules/permission.js`: replace `path: '*'` catch-all with `path: '/:pathMatch(.*)*'` (Vue Router 4 API change)
  - Fixed upstream? [ ]
  - Applied on disk? [x]
- **004** — `vue.config.js`: pin `devServer.client.webSocketURL` so HMR connects through host-side `127.0.0.1:8080` instead of the container's internal IP
  - Fixed upstream? [ ]
  - Applied on disk? [x]
- **005** — `vue.config.js`: disable `devServer.client.overlay.runtimeErrors` to stop element-plus el-menu's benign `getComputedStyle` throw from blanking the dashboard with a red overlay
  - Fixed upstream? [ ]
  - Applied on disk? [x]
- **006** — `App.vue`: remove Baidu Analytics (`hm.baidu.com`) injection from `mounted()` for privacy
  - Fixed upstream? [ ]
  - Applied on disk? [x]
- **007** — `Sidebar/index.vue`: replace deprecated `<el-menu :background-color/:text-color>` props with CSS variables (Element Plus 2.x API change)
  - Fixed upstream? [ ]
  - Applied on disk? [x]

**How to update:**

- **Fixed upstream?** Tick `[x]` when the bug is gone in the fork or upstream. Record the fix commit / date inside the entry detail. Once ticked, the entry is historical reference — keep it.
- **Applied on disk?** Tick `[x]` when the patch is currently applied to the sub-repo working tree. Untick `[ ]` when reverted (`git -C fork260506-go-admin-ui checkout <file>`). The next time the stack starts, unticked items here are your re-apply checklist.

## Entry format

Each patch gets a level-3 heading: `### NNN — short title`. **The entry detail does NOT carry the apply-state — that lives only in the index above.**

**Required fields:**
- **Type:** `patch` (deliberate edit) | `side-effect` (container-induced) | `proposed` (identified, not applied)
- **First applied:** the date the patch was first applied (and a one-line context)
- **Trigger:** the scenario that surfaced the issue
- **File:** exact path relative to sub-repo root
- **Anchor:** line numbers **and** a 1–2 line unique surrounding-context snippet (resists line drift)
- **Change:** before / after diff (unified preferred), or full snippet for both states
- **Detection:** a shell command(s) that **exits 0 iff the patch is currently applied** to the sub-repo on disk. Used by the reconciliation workflow (see [SUBREPOS.md §3](SUBREPOS.md#3-the-rules)) to derive `Applied on disk?` automatically — no manual ticking required.
- **Reason:** root cause in one paragraph
- **Long-term fix:** what *should* happen (PR upstream, refactor, etc.)
- **Recovery:** the exact command(s) to revert the patch + any side-effects (e.g., needs container restart)
- **Related docs:** spec / debug log / other workspace files

---

## Entries

### 001 — Disable `<vue-particles>` in `views/login/index.vue` (Vue 3 migration leftover)

- **First applied:** 2026-05-09 (during sqlite-profile UI verification; required for the login page to render at all)
- **Trigger:** With sqlite profile up and `http://localhost:8080/#/login` open, the page rendered nothing but a webpack-dev-server overlay reading `Uncaught runtime errors: r.component is not a function`. Root view (`#app`) had only ~20 bytes of inner HTML.
- **File:** `src/views/login/index.vue`
- **Anchor:** three sites in the same file
  1. **template, near top** — surrounding context:
     ```vue
     <template>
       <div class="login-container">
         <div id="particles-js">
           <vue-particles v-if="refreshParticles" id="tsparticles" :options="particlesOptions" />
         </div>
         <div class="login-weaper animated bounceInDown">
     ```
  2. **`<script>` import block** — surrounding context (around line 174 at time of patch):
     ```js
     import SocialSign from './components/SocialSignin'
     import Particles from '@tsparticles/vue3'

     export default {
     ```
  3. **`components: { ... }` block** — surrounding context (around line 180):
     ```js
       components: {
         SocialSign,
         VueParticles: Particles
       },
     ```
- **Change:** comment out all three sites. The minimal patch is to wrap the template `<div id="particles-js">…</div>` in an HTML comment, prefix the `import Particles ...` line with `//`, and comment out the `VueParticles: Particles` entry inside `components` (leaving `SocialSign` as the sole registered local component, with no trailing comma).
  - Patched template:
    ```vue
        <!-- vue-particles disabled: @tsparticles/vue3 must be installed via app.use()
             in main.js, not as a local component. main.js:40 has the install
             commented out (Vue 3 migration TODO upstream). -->
        <!-- <div id="particles-js">
          <vue-particles
            v-if="refreshParticles"
            id="tsparticles"
            :options="particlesOptions"
          />
        </div> -->
    ```
  - Patched import:
    ```js
    // import Particles from '@tsparticles/vue3'  // disabled — see template comment
    ```
  - Patched components block:
    ```js
      components: {
        SocialSign
        // VueParticles: Particles  // disabled — see template comment
      },
    ```
- **Detection:**
  ```bash
  # Returns 0 iff the import line is commented out (i.e., the patch is applied).
  grep -qE "^[[:space:]]*//[[:space:]]*import Particles from '@tsparticles/vue3'" \
    fork260506-go-admin-ui/src/views/login/index.vue
  ```
  Run from workspace root. Exit `0` → tick `Applied on disk? [x]` in the index. Non-zero → set to `[ ]` and re-apply per **Change** above before the stack will work again.
- **Reason:** `@tsparticles/vue3`'s default export is a Vue 3 **plugin** object `{ install(app, options) { app.component('vue-particles', VueParticlesComp); ... } }`. The fork's `views/login/index.vue` imports it and then registers it as a **local component** via `components: { VueParticles: Particles }`. Vue 3 sees the plugin object, finds no `render`/`setup`/`template`, and ends up calling `install` itself as the render function. The first line of `install` is `app.component(...)`; the argument Vue passes during render is not the app instance, so `.component` is undefined → TypeError. Meanwhile, `src/main.js:40` has the *correct* registration (`app.use(VueParticles, ...)`) commented out with the note `vue-particles 不支持 Vue 3，需要后续处理`, confirming this is an incomplete Vue 3 migration.
- **Long-term fix:** Restore the global registration in `main.js`:
  ```js
  import Particles from '@tsparticles/vue3'
  // ...
  const app = createApp(App)
  app.use(Particles)   // registers <vue-particles> globally
  ```
  Then in `login/index.vue`, **remove** both the `import Particles ...` and the `VueParticles: Particles` entry from `components`. Keep the `<vue-particles>` element in template — it works because the plugin's `install` already calls `app.component('vue-particles', ...)`. This requires a fork-side PR; not done as part of the workspace's docker-compose work.
- **Recovery:**
  ```bash
  git -C fork260506-go-admin-ui checkout src/views/login/index.vue
  docker compose --profile sqlite restart go-admin-ui   # clear webpack-dev-server in-memory bundle
  ```
  After recovery, the login page will once again be broken until the patch is reapplied or the long-term fix above is shipped.
- **Related docs:**
  - `20260509_cdp9229_debug.md` — full debugging story, CDP techniques used to diagnose this, and the HMR-stuck symptom that required `docker compose restart` after the file edit
  - `SUBREPOS.md` Rule 4 — workspace-level fixes preferred over sub-repo edits; this patch is a deliberate Rule 4 exception (workspace-level fix is not feasible without overlay-mounting a Vue file, which is more invasive than the source edit)

---

### 002 — `permission.js`: replace `router.addRoutes` with `router.addRoute` (Vue Router 4 API change)

- **Type:** patch
- **First applied:** 2026-05-09 (during sqlite-profile login verification; entry 001 fix exposed this second Vue 3 migration gap)
- **Trigger:** With sqlite profile up and credentials correct (`admin` / `123456` / any non-empty captcha — backend is in `mode: dev` so captcha content is unchecked), clicking the 登 录 button leaves the page stuck on `#/login?redirect=/dashboard` with the button frozen at "登 录 中...". Network tab shows `POST /api/v1/login` → 200, `GET /api/v1/getinfo` → 200, `GET /api/v1/menurole` → 200, `Admin-Token` cookie set, vuex `user.token`/`roles` populated — yet the router never lands on `/dashboard`.
- **File:** `src/permission.js`
- **Anchor:** line 43, inside the global `router.beforeEach` guard's `try` block — surrounding context:
  ```js
  // generate accessible routes map based on roles
  const accessRoutes = await store.dispatch('permission/generateRoutes', roles)

  // dynamically add accessible routes
  router.addRoutes(accessRoutes)

  // hack method to ensure that addRoutes is complete
  // set the replace: true, so the navigation will not leave a history record
  next({ ...to, replace: true })
  ```
- **Change:** replace the single-call `router.addRoutes(accessRoutes)` with an iterating `addRoute` per Vue Router 4's API.
  - Patched (one call site only):
    ```js
    // dynamically add accessible routes
    // vue-router 4 removed `addRoutes`; iterate `addRoute` instead.
    accessRoutes.forEach(route => router.addRoute(route))
    ```
- **Detection:**
  ```bash
  # Returns 0 iff the iterating addRoute form is on disk (i.e., the patch is applied).
  grep -qE "accessRoutes\.forEach\(.+=>.+router\.addRoute\(" \
    fork260506-go-admin-ui/src/permission.js
  ```
  Run from workspace root. Exit `0` → tick `Applied on disk? [x]` in the index. Non-zero → set to `[ ]` and re-apply per **Change** above; remember webpack-dev-server's in-memory bundle is sticky on WSL2 (HMR ws fails), so a `docker compose --profile sqlite restart go-admin-ui` is required for the new bundle to reach the browser.
- **Reason:** `package.json` pins `vue@^3.4.0` and `vue-router@^4.4.0`. Vue Router 4 **removed** the `Router.addRoutes(routes)` plural form (it existed in Vue Router 3's Vue 2 era) in favour of `Router.addRoute(route)` for a single route or `Router.addRoute(parentName, route)` for a child. Calling the missing method throws `TypeError: router.addRoutes is not a function` synchronously. Because the call is inside the `try {}` of the `beforeEach` guard, the catch block on line 48 swallows it and runs `next(\`/login?redirect=${to.path}\`)`, redirecting the user **back to /login**. The resulting navigation lands on `/login` from `/login`, which Vue Router rejects as `NavigationFailureType.duplicated (16)` ("Avoided redundant navigation to current location"). Net effect: login succeeds, token is stored, dynamic routes are computed — but the guard rewrites the destination back to login on every attempt, so the user never leaves the login page. CDP verification: instrumenting `router.push`, `beforeEach`, `afterEach`, and `onError` shows the exact sequence `push("/dashboard")` → `afterEach: /login → /login FAILED:16`.
- **Long-term fix:** PR upstream replacing `router.addRoutes(accessRoutes)` with `accessRoutes.forEach(r => router.addRoute(r))`. The fork already migrated `package.json` to vue-router 4 but missed this single API call site (and the `views/login/index.vue` plugin registration documented in entry 001), suggesting the Vue 2→3 migration was partial.
- **Recovery:**
  ```bash
  git -C fork260506-go-admin-ui checkout src/permission.js
  docker compose --profile sqlite restart go-admin-ui   # clear webpack-dev-server in-memory bundle
  ```
  After recovery, login will silently fail again (JWT cookie is set but UI stays on /login) until the patch is reapplied. The WSL2 HMR gap means an edit alone is **not** enough — without the container restart, the browser keeps serving the old bundle even after webpack reports "Build finished".
- **Related docs:**
  - `20260509_cdp9229_debug.md` — CDP techniques used to diagnose this (router instrumentation pattern: hook `push`, `beforeEach`, `afterEach`, `onError`; then read back `window.__rlog`)
  - Entry 001 (vue-particles) — sibling Vue 3 migration leftover surfaced during the same verification session
  - `docs/superpowers/specs/20260508a_workspace-docker-compose-design.md` §5 troubleshooting — explains the WSL2 inotify gap that makes the container restart mandatory after sub-repo edits

---

### 003 — `store/modules/permission.js`: replace `path: '*'` catch-all with `path: '/:pathMatch(.*)*'` (Vue Router 4 API change)

- **Type:** patch
- **First applied:** 2026-05-09 (immediately after entry 002 — fixing entry 002 exposed this third Vue 3 migration gap)
- **Trigger:** With entry 002 in place, login click still leaves the page stuck on `#/login?redirect=/dashboard`. CDP probing confirmed `hasToken=YES` and `to.path='/dashboard'` (so the guard takes the `try {}` branch in `permission.js`), then captured the catch:
  ```
  Error: Catch all routes ("*") must now be defined using a param with a custom regexp.
  See more at https://router.vuejs.org/guide/migration/#Removed-...
  ```
  i.e., the `forEach(addRoute)` from entry 002 is throwing on the very last asyncRoute, which has the legacy `path: '*'` catch-all syntax. The `catch` block then runs `next(\`/login?redirect=${to.path}\`)`, which lands on /login → /login → `NavigationFailureType.duplicated (16)`.
- **File:** `src/store/modules/permission.js`
- **Anchor:** line 150, inside the `getRouters` action's success branch — surrounding context:
  ```js
  generaMenu(asyncRoutes, loadMenuData)
  asyncRoutes.push({ path: '*', redirect: '/', hidden: true })
  commit('SET_ROUTES', asyncRoutes)
  ```
- **Change:** swap the legacy `*` form for vue-router 4's named-param-with-regexp catch-all.
  - Patched:
    ```js
    // vue-router 4 dropped `path: '*'` catch-all; use named param with regexp instead.
    asyncRoutes.push({ path: '/:pathMatch(.*)*', redirect: '/', hidden: true })
    ```
- **Detection:**
  ```bash
  # Returns 0 iff the new catch-all syntax is on disk (i.e., the patch is applied).
  grep -qE "path:\s*['\"]/:pathMatch\(\.\*\)\*['\"]" \
    fork260506-go-admin-ui/src/store/modules/permission.js
  ```
  Run from workspace root.
- **Reason:** Vue Router 4 (per the official migration guide) removed the `*` shorthand for catch-all routes — they must now be expressed as a named parameter with a custom regexp, e.g. `/:pathMatch(.*)*` (greedy zero-or-more) or `/:pathMatch(.*)` (single segment). Calling `router.addRoute({ path: '*', ... })` throws synchronously in vue-router 4. Because that `addRoute` call sits inside the `try {}` of `permission.js`'s navigation guard (entry 002 introduced this iteration), the exception is swallowed, all earlier route additions are partially applied (visible as the `routes_count` going from 12 to 34 in CDP probes), and the fallback `next('/login?redirect=...')` redirects the user back to login — same external symptom as entry 002, but a different cause one layer deeper.
- **Long-term fix:** PR upstream replacing `path: '*'` with `path: '/:pathMatch(.*)*'`. This is a single-line, mechanical migration covered by vue-router's own migration guide. Combined with entry 002, this completes the dynamic-routing migration.
- **Recovery:**
  ```bash
  git -C fork260506-go-admin-ui checkout src/store/modules/permission.js
  docker compose --profile sqlite restart go-admin-ui   # clear webpack-dev-server in-memory bundle
  ```
  After recovery, login will re-fail in the same way as entry 002's symptom (NavigationFailure 16 → stuck on /login). Reapply per **Change** above.
- **Related docs:**
  - Entry 002 — sibling Vue Router 4 migration; this entry was only discovered after entry 002 unblocked the `addRoute` call site.
  - Vue Router migration guide: https://router.vuejs.org/guide/migration/#Removed-star-or-catch-all-routes

---

### 004 — `vue.config.js`: pin `devServer.client.webSocketURL` for HMR through docker port mapping

- **Type:** patch
- **First applied:** 2026-05-09 (during the post-login HMR investigation, after entries 002+003 unstuck the dashboard navigation)
- **Trigger:** Browser console keeps showing
  ```
  WebSocket connection to 'ws://172.19.0.2:8080/ws' failed:
    Error in connection establishment: net::ERR_CONNECTION_TIMED_OUT
  ```
  on every page load. `172.19.0.2` is the go-admin-ui container's address on the docker bridge network — unreachable from the host browser.
- **File:** `vue.config.js`
- **Anchor:** the `module.exports.devServer.client` block (around line 39 at time of patch) — surrounding context:
  ```js
  devServer: {
    port: port,
    open: false,
    client: {
      overlay: { warnings: false, errors: true }
    }
  },
  ```
- **Change:** add `webSocketURL: 'auto://0.0.0.0:0/ws'` inside the `client` block. With this value, webpack-dev-server's client-side bundle picks up the **page's own** host and port (which the host browser DID reach successfully — `127.0.0.1:8080`), instead of the container-side IP webpack-dev-server detects when binding `0.0.0.0`.
  - Patched:
    ```js
    devServer: {
      port: port,
      open: false,
      client: {
        overlay: { warnings: false, errors: true },
        // Without this, webpack-dev-server 4 picks the container's internal IP
        // (e.g. 172.19.0.2) for the HMR socket URL, which the host browser cannot
        // reach. `auto://0.0.0.0:0/ws` makes the client use the page's own host
        // and port, so it connects back through the docker port mapping.
        webSocketURL: 'auto://0.0.0.0:0/ws'
      }
    },
    ```
- **Detection:**
  ```bash
  # Returns 0 iff the webSocketURL pin is on disk.
  grep -qE "webSocketURL:\s*['\"]auto://0\.0\.0\.0:0/ws['\"]" \
    fork260506-go-admin-ui/vue.config.js
  ```
- **Reason:** webpack-dev-server 4's default for `client.webSocketURL` is `auto://[host-it-bound-to]:[port]/ws`. Inside a docker container, the bound address is the bridge-network IP (`172.19.0.2`), so the **client** bundle (running in the host's browser) tries to open `ws://172.19.0.2:8080/ws` — which the host has no route to. Hard-coding `auto://0.0.0.0:0/ws` tells the client to use the **page's** `location.host`/`location.port` instead, so it reconnects through the same `127.0.0.1:8080` docker port mapping the user already used to reach the page. This restores HMR for `.vue`/`.js` edits — though note: WSL2 + NTFS bind-mount also needs the polling env vars in `docker-compose.yml` (see spec §5) for chokidar to actually detect file changes. The two fixes are complementary: polling catches the change, this WS fix delivers the HMR reload to the browser.
- **Long-term fix:** PR upstream replicating the comment + setting. The `auto://0.0.0.0:0/ws` value is harmless for non-docker dev (it just uses the same hostname the page was loaded from) and removes the docker-specific footgun.
- **Recovery:**
  ```bash
  git -C fork260506-go-admin-ui checkout vue.config.js
  docker compose --profile sqlite restart go-admin-ui
  ```
  After recovery, HMR ws will once again target the container IP and fail. Edits to `.vue`/`.js` files won't reach the browser without a manual `docker compose ... restart go-admin-ui` (which is exactly the workaround documented in `20260509_cdp9229_debug.md`).
- **Related docs:**
  - `docs/superpowers/specs/20260508a_workspace-docker-compose-design.md` §5 troubleshooting — WSL2 inotify gap entry (the polling env vars are the *file-watch* half; this entry is the *delivery* half)
  - `20260509_cdp9229_debug.md` — observed the `ws://172.19.0.2:8080/ws` failure during initial CDP debugging; that doc now points at this fix as the permanent answer
  - webpack-dev-server docs: https://webpack.js.org/configuration/dev-server/#websocketurl

---

### 005 — `vue.config.js`: disable `devServer.client.overlay.runtimeErrors`

- **Type:** patch
- **First applied:** 2026-05-09 (after the dashboard rendered cleanly, a red full-page overlay was blocking interaction whenever el-menu's resize logic triggered)
- **Trigger:** With entries 002+003 fixed, `/dashboard` renders correctly — but the moment the menu re-measures (initial mount, viewport resize, route switch), a runtime error fires:
  ```
  Failed to execute 'getComputedStyle' on 'Window': parameter 1 is not of type 'Element'.
    at calcMenuItemWidth (chunk-vendors.js — element-plus el-menu source)
    at calcSliceIndex
    at ResizeObserver.handleResize
  ```
  The error itself is *benign* (the menu still renders) but webpack-dev-server's `client.overlay` paints the entire viewport red with the stack trace, blocking the user from seeing or clicking the dashboard. Screenshot: `_temp_/Screenshot 2026-05-09 043435.png`.
- **File:** `vue.config.js`
- **Anchor:** `module.exports.devServer.client.overlay` block (alongside entry 004's edit) — surrounding context after this patch:
  ```js
  client: {
    overlay: {
      warnings: false,
      errors: true,
      runtimeErrors: false  // <-- this entry
    },
    webSocketURL: 'auto://0.0.0.0:0/ws'  // <-- entry 004
  }
  ```
- **Change:** add `runtimeErrors: false` inside the `overlay` object. webpack-dev-server 4.6+ honours this flag — runtime exceptions still log to the JS console, but the full-page overlay stays out of the way. Compile-time errors (which DO need attention) still surface.
- **Detection:**
  ```bash
  grep -qE "runtimeErrors:\s*false" fork260506-go-admin-ui/vue.config.js
  ```
- **Reason:** The underlying throw is in element-plus 2.13.7's `el-menu` `calcSliceIndex`/`calcMenuItemWidth`:
  ```js
  Array.from(menu.value.childNodes)
    .filter(item => item.nodeName !== "#comment" && (item.nodeName !== "#text" || item.nodeValue))
  ```
  The filter retains text nodes whose `nodeValue` is non-empty (e.g. whitespace), then passes them to `getComputedStyle`, which only accepts `Element`. The fix in element-plus would be `item.nodeType === 1` (Element check). Verified against npm: **element-plus 2.14.0 (latest as of 2026-05-09) ships the same buggy filter**, so upgrading the dependency does not help. Patching `node_modules/element-plus` directly would be erased by `npm install`. Suppressing the *overlay* (not the error) is the cheapest fix that lets the dashboard be usable without misrepresenting that no error occurred — devs who care can still see it in DevTools.
- **Long-term fix:** PR upstream into `element-plus` to change the filter to `item.nodeType === Node.ELEMENT_NODE` (or `=== 1`). Once a fixed element-plus version ships and the fork bumps to it, this `runtimeErrors: false` line can be removed (the underlying throw is gone).
- **Recovery:**
  ```bash
  git -C fork260506-go-admin-ui checkout vue.config.js   # also reverts entry 004's edit
  docker compose --profile sqlite restart go-admin-ui
  ```
  After recovery, the red overlay will reappear on every dashboard load; users will be unable to click anything until they dismiss it (which the overlay does not provide a button for, so it requires hard-reload after fixing the config).
- **Related docs:**
  - Entry 004 — sibling vue.config.js patch in the same `client` block (different concern: HMR socket URL vs. error overlay)
  - element-plus issue tracker — search "calcMenuItemWidth getComputedStyle" or "el-menu ResizeObserver"
  - webpack-dev-server overlay docs: https://webpack.js.org/configuration/dev-server/#overlay

---

### 006 — `App.vue`: remove Baidu Analytics injection from `mounted()`

- **Type:** patch
- **First applied:** 2026-05-09 (during external-resource audit)
- **Trigger:** CDP capture of all non-`127.0.0.1` requests during login → dashboard flow showed `https://hm.baidu.com/hm.js?…` + `hm.gif` tracking pixels firing on every page load. The `hm.gif` request encodes the full SPA URL (`u=http://127.0.0.1:8080/#/login?redirect=/dashboard`) — i.e., dev session activity is being uploaded to a third-party analytics service in China. Findings recorded in `20260509_cdp9229_external-resources-audit.md`.
- **File:** `src/App.vue`
- **Anchor:** the `<script>` block — surrounding context (around line 7-22 at time of patch):
  ```vue
  <script>
  export default {
    name: 'App',
    mounted() {
      // 声明: 百度统计统计相关下载使用量无别的用途
      // 可自行删除
      var _hmt = _hmt || []
      ;(function() {
        var hm = document.createElement('script')
        hm.src = 'https://hm.baidu.com/hm.js?1d2d61263f13e4b288c8da19ad3ff56d'
        var s = document.getElementsByTagName('script')[0]
        s.parentNode.insertBefore(hm, s)
      })()
    }
  }
  </script>
  ```
- **Change:** delete the entire `mounted()` method body. The component then has no lifecycle hook beyond `name`. Replace with a short comment explaining why.
  - Patched:
    ```vue
    <script>
    // Baidu Analytics injection (hm.baidu.com) was removed for privacy:
    // every page load was reporting the full SPA URL (incl. dev paths)
    // to a third-party tracker on every dev session. See workspace
    // fork260506-go-admin-ui.md entry 006.
    export default {
      name: 'App'
    }
    </script>
    ```
- **Detection:**
  ```bash
  # Returns 0 iff the patch is applied (the `_hmt` global var, only present in the
  # original Baidu injection code, is gone). NB: the patched file's comment still
  # mentions `hm.baidu.com` for context, so we cannot just grep the domain name.
  ! grep -q "_hmt" fork260506-go-admin-ui/src/App.vue
  ```
  Note the leading `!` — we want the marker **absent**.
- **Reason:** The original code (a remnant from `vue-element-admin`'s upstream demo) self-reported via Baidu's analytics service, designed for tracking page views in production. In a dev/internal context this:
  1. Sends the full SPA URL (including `127.0.0.1:8080` and any redirect query params) to `hm.baidu.com` on every page load
  2. Wastes bandwidth + adds 1 external script + 1+ pixel beacon to every navigation
  3. Has no value for this fork (no Baidu Analytics dashboard is configured for this site ID)
  Removing the snippet is purely subtractive and has no functional impact.
- **Long-term fix:** PR upstream removing the Baidu loader from the template. The original vue-element-admin upstream may want to gate this on an env var rather than removing — but for this fork the cleanest action is deletion.
- **Recovery:**
  ```bash
  git -C fork260506-go-admin-ui checkout src/App.vue
  docker compose --profile sqlite restart go-admin-ui
  ```
  After recovery, every page load again pings `hm.baidu.com`.
- **Related docs:**
  - `20260509_cdp9229_external-resources-audit.md` §1.3 — documented the exact hm.baidu.com calls captured

---

### 007 — `Sidebar/index.vue`: switch to CSS variables for menu theme (Element Plus 2.x deprecation)

- **Type:** patch
- **First applied:** 2026-05-09 (after dashboard render screenshot showed sidebar items rendered as **white text on white background** — invisible)
- **Trigger:** With theme = `dark`, the screenshot of the dashboard sidebar showed items 1–N visually empty below the "go-admin管理系統" header. CDP `getComputedStyle` confirmed:
  ```
  .el-menu          { background-color: rgb(255,255,255), color: rgb(0,0,0) }   ← unchanged from EP defaults
  .el-menu-item     { color: rgb(255,255,255), background: transparent }        ← white text
  ```
  → white text on a white container = invisible. The `<el-menu :background-color="...">` prop was set on the source side but had no effect on the rendered styles.
- **File:** `src/layout/components/Sidebar/index.vue`
- **Anchor:** the `<el-menu>` template element (lines 5–14 at time of patch) and the `computed:` block (around line 35–58):
  ```vue
  <el-menu
    :default-active="activeMenu"
    :collapse="isCollapse"
    :background-color=" $store.state.settings.themeStyle === 'light' ? variables.menuLightBg : variables.menuBg"
    :text-color="$store.state.settings.themeStyle === 'light' ? 'rgba(0,0,0,.65)' : '#fff'"
    :active-text-color="$store.state.settings.theme"
    :unique-opened="true"
    :collapse-transition="true"
    mode="vertical"
  >
  ```
- **Change:** drop the three deprecated colour props from the template; pass an inline `:style` mapping the **CSS custom properties** Element Plus 2.x actually consumes; compute the values in a new `menuCssVars` computed.
  - Patched template:
    ```vue
    <el-menu
      :default-active="activeMenu"
      :collapse="isCollapse"
      :style="menuCssVars"
      :unique-opened="true"
      :collapse-transition="true"
      mode="vertical"
    >
    ```
  - New computed (added inside `computed: { ... }`):
    ```js
    menuCssVars() {
      // Note: scss `:export` produces an empty object under Vue CLI 5 / sass-loader
      // 13+, so we cannot read tokens from `variables` here. Mirror the values
      // from `src/styles/variables.scss` literally — keep the two files in sync
      // if the palette changes.
      const isLight = this.$store.state.settings.themeStyle === 'light'
      return {
        '--el-menu-bg-color': isLight ? '#ffffff' : '#001529',
        '--el-menu-hover-bg-color': isLight ? '#f0f1f5' : '#000c17',
        '--el-menu-text-color': isLight ? 'rgba(0,0,0,.65)' : '#fff',
        '--el-menu-active-color': this.$store.state.settings.theme
      }
    }
    ```
  - **Why hardcoded values**: under Vue CLI 5 / sass-loader 13+, `import variables from '@/styles/variables.scss'` returns an empty object — `:export` is a css-modules feature that requires the file to be processed as a CSS Module. CDP debug confirmed `variables = {}` at runtime, which silently dropped 3 of the 4 CSS vars from the inline style. Rather than reconfigure the loader chain (touches webpack config, broader blast radius), this entry mirrors the scss palette as JS literals at this single call site.
- **Detection:**
  ```bash
  # Returns 0 iff the new computed is in place.
  grep -q "menuCssVars" fork260506-go-admin-ui/src/layout/components/Sidebar/index.vue
  ```
- **Reason:** Element Plus 2.x marked the `<el-menu>` colour props (`background-color`, `text-color`, `active-text-color`) as deprecated and reads colours from CSS custom properties (`--el-menu-bg-color`, `--el-menu-text-color`, `--el-menu-active-color`, `--el-menu-hover-bg-color`) instead. The fork's source still passes the old props — they're silently ignored, leaving the menu painted with the EP defaults (white background, white text on dark hover). When the surrounding theme is `dark`, the result is white-on-white invisibility. CDP runtime probe confirmed: setting the four CSS vars on `.el-menu` immediately restored visibility (bg → `rgb(0,21,41)`, items → white visible against dark).
- **Long-term fix:** PR upstream replacing these props at every `<el-menu>` call site. The Element Plus migration guide explicitly recommends this swap. There may be additional `<el-menu>` instances elsewhere (e.g., TopNav) — they should be audited similarly.
- **Recovery:**
  ```bash
  git -C fork260506-go-admin-ui checkout src/layout/components/Sidebar/index.vue
  docker compose --profile sqlite restart go-admin-ui   # bundle rebuild
  ```
  After recovery, sidebar text becomes invisible again under `dark` theme.
- **Related docs:**
  - `_temp_/Screenshot 2026-05-09 052959.png` — original observation (white-on-white sidebar)
  - Element Plus migration: https://element-plus.org/en-US/component/menu.html (see "CSS Variables" section)

---

## Revision log

| Date | Change |
|---|---|
| 2026-05-09 | Initial scaffold; documented entry 001 (vue-particles plugin-as-component) |
| 2026-05-09 | Documented entry 002 (vue-router 4 `addRoutes` → `addRoute` migration) |
| 2026-05-09 | Documented entry 003 (vue-router 4 `path: '*'` catch-all migration) |
| 2026-05-09 | Documented entry 004 (vue.config.js HMR `webSocketURL` for docker bridge networking) |
| 2026-05-09 | Documented entry 005 (vue.config.js disable runtime-error overlay covering dashboard) |
| 2026-05-09 | Documented entry 006 (App.vue remove Baidu Analytics for privacy) |
| 2026-05-09 | Documented entry 007 (Sidebar/index.vue switch <el-menu> theme to CSS variables) |
