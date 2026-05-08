# fork260506-go-admin: Workspace Patch Log

> Companion to [SUBREPOS.md](SUBREPOS.md). Per SUBREPOS.md **Rule 1** sub-repo
> changes never enter this workspace's git history, and per **Rule 3** the
> sub-repo's working tree may be reverted at any time. This file is the
> durable memory that lets us **re-apply** active patches and **understand
> why** each one exists.
>
> Sub-repo upstream remote: see `git -C fork260506-go-admin remote -v`.
> Sub-repo branch in scope: typically `main`.

## Patches index

**Single source of truth for each patch's lifecycle (Fixed upstream?) and apply-state (Applied on disk?).**
On a fresh session — or after reverting the sub-repo — scan for any item where **both boxes are unticked**; those are the patches that need to be re-applied before bringing up the stack.

- **001** — `go.mod` may be modified by container's `go mod tidy`
  - Fixed upstream? [ ]
  - Applied on disk? *(N/A — side-effect, auto-applied by `scripts/backend-entrypoint.sh` on each fresh container)*

**How to update:**

- **Fixed upstream?** Tick `[x]` when the bug is gone in the fork or upstream. Record the fix commit / date inside the entry detail. Once ticked, the entry is historical reference — keep it.
- **Applied on disk?** Tick `[x]` when the patch is currently applied to the sub-repo working tree. Untick `[ ]` when reverted. For **side-effect** entries (`N/A`), this column is not used — those are container behaviours, not deliberate patches.

## Entry format

Each patch gets a level-3 heading: `### NNN — short title`. **The entry detail does NOT carry the apply-state — that lives only in the index above.**

**Required fields:**
- **Type:** `patch` (deliberate edit) | `side-effect` (container-induced behaviour) | `proposed` (identified, not yet applied)
- **First applied / observed:** the date the patch was first applied (or, for side-effects, when it was first noticed)
- **Trigger:** the scenario that surfaced the issue
- **File:** exact path relative to sub-repo root
- **Anchor:** line numbers **and** a 1–2 line unique surrounding-context snippet (resists line drift)
- **Change:** before / after diff (unified preferred), or full snippet for both states; for side-effects, describe what the container does
- **Reason:** root cause in one paragraph
- **Long-term fix:** what *should* happen (PR upstream, refactor, etc.)
- **Recovery:** the exact command(s) to revert (or "auto-recovers next clean start" for side-effects)
- **Related docs:** spec / debug log / other workspace files

---

## Entries

### 001 — `go.mod` may be modified by container's `go mod tidy`

- **Type:** side-effect (recurring container behaviour, not a deliberate patch)
- **First observed:** 2026-05-08 (mysql smoke test)
- **Trigger:** Backend container's `scripts/backend-entrypoint.sh` runs `go mod tidy` when `go.sum` is missing on the bind-mounted source. Tidy may rewrite `go.mod` (e.g., `imdario/mergo v0.3.13` → `dario.cat/mergo v1.0.1` rename).
- **File:** `go.mod`
- **Anchor:** the `require ( ... // indirect )` block; specifically the `imdario/mergo` line which gets replaced by `dario.cat/mergo`
- **Change:** automatic; produced by `go mod tidy` not by us
- **Reason:** `go.sum` is `.gitignore`d in this fork. First-run bind-mount has no `go.sum`. `go mod download` alone does not populate transitive `go.sum`; only `go mod tidy` does, and tidy normalizes module paths along the way.
- **Long-term fix:** Workspace-level pre-baked `go.mod` / `go.sum` overlay bind-mount (option already noted in `docs/superpowers/specs/20260508a_workspace-docker-compose-design.md` §5). Implementing that is a separate workspace task.
- **Recovery (after smoke test):**
  ```bash
  git -C fork260506-go-admin checkout go.mod
  ```
  `go.sum` is gitignored upstream so it does not need reverting.
- **Related docs:**
  - `docs/superpowers/specs/20260508a_workspace-docker-compose-design.md` §2.7, §5
  - `20260509_cdp9229_debug.md` (HMR-related, but same general "container side-effects on sub-repo files" theme)

---

## Revision log

| Date | Change |
|---|---|
| 2026-05-09 | Initial scaffold; documented entry 001 (go.mod tidy side-effect) |
