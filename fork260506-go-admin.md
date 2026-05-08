# fork260506-go-admin: Workspace Patch Log

> Companion to [SUBREPOS.md](SUBREPOS.md). Per SUBREPOS.md **Rule 1** sub-repo
> changes never enter this workspace's git history, and per **Rule 3** the
> sub-repo's working tree may be reverted at any time. This file is the
> durable memory that lets us **re-apply** active patches and **understand
> why** each one exists.
>
> Sub-repo upstream remote: see `git -C fork260506-go-admin remote -v`.
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

### 001 — `go.mod` may be modified by container's `go mod tidy`

- **Status:** ⏸ DORMANT (recurring side-effect, not a patch I apply intentionally; documented so it's not mistaken for vandalism)
  - First observed: 2026-05-08 mysql smoke test
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
