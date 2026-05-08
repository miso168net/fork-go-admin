# fork260506-go-admin-doc: Workspace Patch Log

> Companion to [SUBREPOS.md](SUBREPOS.md). Per SUBREPOS.md **Rule 1** sub-repo
> changes never enter this workspace's git history, and per **Rule 3** the
> sub-repo's working tree may be reverted at any time. This file is the
> durable memory that lets us **re-apply** active patches and **understand
> why** each one exists.
>
> Sub-repo upstream remote: see `git -C fork260506-go-admin-doc remote -v`.
> Sub-repo branch in scope: typically `main`.
>
> **Note:** This sub-repo is **not** containerized by the workspace
> docker-compose stack (intentional, per
> [spec §0.3](docs/superpowers/specs/20260508a_workspace-docker-compose-design.md)
> non-goals). Run standalone with `pnpm dev` if you need the dumi site.

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

*(no patches recorded yet)*

---

## Revision log

| Date | Change |
|---|---|
| 2026-05-09 | Initial scaffold |
