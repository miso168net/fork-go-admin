# fork260506-go-admin-ui: Workspace Patch Log

> Companion to [SUBREPOS.md](SUBREPOS.md). Per SUBREPOS.md **Rule 1** sub-repo
> changes never enter this workspace's git history, and per **Rule 3** the
> sub-repo's working tree may be reverted at any time. This file is the
> durable memory that lets us **re-apply** active patches and **understand
> why** each one exists.
>
> Sub-repo upstream remote: see `git -C fork260506-go-admin-ui remote -v`.
> Sub-repo branch in scope: typically `main`.

## Status legend

- 🔧 **ACTIVE** — currently needed; sub-repo on disk should have this applied
- ⏸ **DORMANT** — was needed previously; not applied right now; kept for reference
- ✅ **RESOLVED** — fork / upstream fixed; entry kept as historical reference
- 📝 **PROPOSED** — identified but not yet applied

## Entry format

Each patch gets a level-3 heading: `### NNN — short title`.

**Required fields:**
- **Status:** one legend value + date(s)
- **Trigger:** the scenario that surfaced the issue
- **File:** exact path relative to sub-repo root
- **Anchor:** line numbers **and** a 1–2 line unique surrounding-context snippet (resists line drift)
- **Change:** before / after diff (unified preferred), or full snippet for both states
- **Reason:** root cause in one paragraph
- **Long-term fix:** what *should* happen (PR upstream, refactor, etc.)
- **Related docs:** spec / debug log / other workspace files

---

## Entries

### 001 — Disable `<vue-particles>` in `views/login/index.vue` (Vue 3 migration leftover)

- **Status:** 🔧 ACTIVE (applied 2026-05-09 during sqlite profile UI verification; required for the login page to render at all)
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

## Revision log

| Date | Change |
|---|---|
| 2026-05-09 | Initial scaffold; documented entry 001 (vue-particles plugin-as-component) |
