# fork260506-redis-watcher: Workspace Patch Log

> Companion to [SUBREPOS.md](SUBREPOS.md). Per SUBREPOS.md **Rule 1** sub-repo
> changes never enter this workspace's git history, and per **Rule 3** the
> sub-repo's working tree may be reverted at any time. This file is the
> durable memory that lets us **re-apply** active patches and **understand
> why** each one exists.
>
> Sub-repo upstream remote: see `git -C fork260506-redis-watcher remote -v`.
> Sub-repo branch in scope: typically `main`.
>
> **Note:** Library-only sub-repo (no service). Linked into the backend via
> `go.work` `use` directive at workspace level.

## Patches index

**Single source of truth for each patch's lifecycle (Fixed upstream?) and apply-state (Applied on disk?).**
On a fresh session — or after reverting the sub-repo — scan for any item where **both boxes are unticked**; those are the patches that need to be re-applied before bringing up the stack.

*(no patches recorded yet)*

**How to update once entries exist:**

- **Fixed upstream?** Tick `[x]` when the bug is gone in the fork or upstream. Record the fix commit / date inside the entry detail. Once ticked, the entry is historical reference — keep it.
- **Applied on disk?** Tick `[x]` when the patch is currently applied to the sub-repo working tree. Untick `[ ]` when reverted (`git -C fork260506-redis-watcher checkout <file>`).

## Entry format

Each patch gets a level-3 heading: `### NNN — short title`. **The entry detail does NOT carry the apply-state — that lives only in the index above.**

**Required fields:**
- **Type:** `patch` (deliberate edit) | `side-effect` (container-induced) | `proposed` (identified, not applied)
- **First applied / observed:** date + one-line context
- **Trigger:** the scenario that surfaced the issue
- **File:** exact path relative to sub-repo root
- **Anchor:** line numbers **and** a 1–2 line unique surrounding-context snippet (resists line drift)
- **Change:** before / after diff or full snippet for both states
- **Detection:** a shell command that **exits 0 iff the patch is currently applied** to the sub-repo on disk. Drives the reconciliation workflow that auto-syncs `Applied on disk?` in the index (see [SUBREPOS.md §3](SUBREPOS.md#3-the-rules)).
- **Reason:** root cause in one paragraph
- **Long-term fix:** what *should* happen (PR upstream, refactor, etc.)
- **Recovery:** the exact command(s) to revert
- **Related docs:** spec / debug log / other workspace files

---

## Entries

*(no patches recorded yet)*

---

## Revision log

| Date | Change |
|---|---|
| 2026-05-09 | Initial scaffold |
