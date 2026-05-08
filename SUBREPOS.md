# Working with the `fork260506-*` Sub-repos

> **Audience:** Anyone (human or AI) operating in this workspace.
> **Status:** Companion to `CLAUDE.md`. CLAUDE.md says **what to read** before answering codebase questions; this file says **what to do and not do** when changes happen.
> **Last updated:** 2026-05-09

---

## 1. Mental model

```
fork-go-admin/                          ← workspace repo (this directory; remote: miso168net/fork-go-admin)
│   .git/                               ← tracks ONLY the umbrella docs
│   .gitignore  ──── ignores `fork260506-*` and `_temp_`
│   docker-compose.yml, go.work, config/, scripts/, docs/, *.md
│
├── fork260506-go-admin/                ← independent fork repo (its own .git, its own remote)
├── fork260506-go-admin-core/           ← independent fork repo
├── fork260506-go-admin-doc/            ← independent fork repo
├── fork260506-go-admin-ui/             ← independent fork repo
├── fork260506-gorm-adapter/            ← independent fork repo
├── fork260506-redis-watcher/           ← independent fork repo
└── fork260506-redisqueue/              ← independent fork repo
```

The workspace repo and the seven sub-repos **share the filesystem but not history**. They are **eight independent Git repos** colocated for ergonomic editing and Docker bind-mounts. Treat each sub-repo as a guest you cannot speak for.

### Project map

| Sub-repo | Language | Role | Runnable as service? |
|---|---|---|---|
| `fork260506-go-admin` | Go 1.24 | Backend admin API (`main.go`, gin) | ✅ via `docker-compose` |
| `fork260506-go-admin-ui` | Vue 3 + vue-cli | Frontend admin UI | ✅ via `docker-compose` |
| `fork260506-go-admin-doc` | dumi 2 (TS/MDX) | Documentation site | ❌ (intentionally out of scope; run standalone if needed) |
| `fork260506-go-admin-core` | Go 1.25 | SDK runtime (queue, ctx helpers, …) | ❌ library |
| `fork260506-gorm-adapter` | Go 1.14+ | casbin adapter for GORM | ❌ library |
| `fork260506-redis-watcher` | Go 1.20+ | casbin redis watcher | ❌ library |
| `fork260506-redisqueue` | Go 1.20+ | redis-backed queue | ❌ library |

---

## 2. The rules

### Rule 1 — Sub-repo changes never enter workspace history

`fork260506-*/` is in `<workspace>/.gitignore`, so `git add` from workspace root cannot accidentally stage a sub-repo file. But the rule is broader than that:

> **Any file inside a `fork260506-*/` directory belongs to that sub-repo's history. The workspace repo must never commit, reference, or carry forward those edits.**

If you (or a tool) find yourself modifying something under a sub-repo:

- ✅ The change is fine on disk during a session (build artifacts, runtime writes, ad-hoc patches for testing).
- ❌ It must NOT be committed via the workspace repo.
- ⚠ If it should persist, it must be committed inside the sub-repo's own `.git`, on a sub-repo branch, pushed to the sub-repo's own remote — and that requires deliberate, explicit authorization for fork-side work.

### Rule 2 — Read GRAPH_REPORT.md before answering code questions

(Restated from `CLAUDE.md`.) Each sub-repo has its own `graphify-out/GRAPH_REPORT.md`. Before answering an architecture / code question about a project, load that report first. For cross-project questions, load all seven.

### Rule 3 — Container-induced dirty state is expected and disposable

Smoke-testing the docker-compose stack regularly produces tracked-file modifications **inside the sub-repos**:

| Source | Effect |
|---|---|
| `scripts/backend-entrypoint.sh` runs `go mod tidy` (when `go.sum` is missing) | `fork260506-go-admin/go.mod` may pick up renamed indirect deps (e.g. `imdario/mergo` → `dario.cat/mergo`). `go.sum` is upstream-gitignored so its presence/absence is invisible to git. |
| Backend writes app logs | `fork260506-go-admin/temp/logs/` populated (gitignored upstream) |
| `npm install` inside frontend container | `fork260506-go-admin-ui/node_modules/` populated (gitignored upstream) |
| Live-edit fixes during debugging | Any `.vue` / `.go` file you touched on disk |

**Before** restoring, decide: was the change just container-induced (revert freely) or a **deliberate patch you applied** (e.g. a hotfix to make the stack work)? In the second case, **record the patch in `fork260506-<name>.md` first** — see those files' "Entry format" section. Reverting without recording loses the working knowledge.

**After a verification session, restore sub-repos to clean tracked state:**

```bash
for d in fork260506-*/; do
  ( cd "$d" && git checkout -- . )
done

# Verify
for d in fork260506-*/; do
  ( cd "$d" && echo "=== $d ===" && git status --short --branch )
done
```

This reverts modifications to **tracked** files only. Untracked / gitignored artifacts (`temp/`, `node_modules/`, `go.sum`, `go-admin-db.db` runtime writes) remain in place — they are harmless and accelerate the next start.

### Rule 4 — Workspace-level fixes for sub-repo issues

When a sub-repo bug needs to be worked around to make the umbrella stack usable, the **default** is:

1. Document the bug and the long-term fix in the workspace spec / debug log.
2. Apply the **minimal** workaround — at the workspace level if possible (compose env override, bind-mount overlay, entrypoint script tweak), inside the sub-repo only as a last resort.
3. If you must touch sub-repo files for verification, treat the edit as a temporary patch, **record it in the matching `fork260506-<name>.md`** (so it's reproducible), and revert (Rule 3) when done.

> Example from the 2026-05-08 docker-compose smoke test: `fork260506-go-admin-core` has an API-incompatible divergence from upstream that breaks `go.work`. The workspace fix was to **exclude** it from `go.work` (workspace-level), not to monkey-patch the fork.
> See `docs/superpowers/specs/20260508a_workspace-docker-compose-design.md` §2.4 + §5.

### Rule 5 — Branch ↔ sub-repo branch independence

The workspace's branch state has **no relationship** to the sub-repos' branch states. They can be on `main`, `feature/x`, a detached HEAD, or anything else.

Before assuming a sub-repo is "current", check:

```bash
for d in fork260506-*/; do
  ( cd "$d" && echo "$d $(git symbolic-ref --short -q HEAD || git rev-parse HEAD) $(git status --short --branch | head -1)" )
done
```

The umbrella docker-compose **bind-mounts whatever is on disk in each sub-repo right now**, regardless of branch. Switching a sub-repo's branch while containers are running is fine for code; for `go.mod` / `package.json` changes, you may need to restart the affected service to pick them up.

---

## 3. Quick recipes

### Pre-flight before bringing up the stack — scan patch logs

Before `docker compose --profile {mysql,sqlite} up`, scan all seven `fork260506-*.md`
files for active patches that are **not yet applied** on disk (i.e., rows in the
"Patches index" where both **Fixed upstream?** and **Applied on disk?** are
unticked):

```bash
# Quick visual scan (open each file's "Patches index" section)
for f in fork260506-*.md; do
  echo "=== $f ==="
  awk '/^## Patches index/,/^## /' "$f" | head -40
done

# Or grep for entries needing re-apply (both checkboxes unticked):
grep -B1 -A1 "Applied on disk\\?\\s*\\[ \\]" fork260506-*.md
```

If you find any unticked-both rows: re-apply the patch (entry detail has the
exact code change), then tick "Applied on disk? `[x]`" in the index.

### Restore all sub-repos to clean state

```bash
for d in fork260506-*/; do
  ( cd "$d" && git checkout -- . && echo "✓ $d" )
done
```

> ⚠ After running this, **untick "Applied on disk?"** in any patch log entry that
> was reverted, so the next session knows to re-apply.

### Snapshot the state of all eight repos (workspace + 7 sub-repos)

```bash
echo "=== workspace ==="
git status --short --branch
git log --oneline -3

for d in fork260506-*/; do
  echo
  echo "=== $d ==="
  ( cd "$d" && git status --short --branch && git log --oneline -3 )
done
```

### Confirm a sub-repo wasn't accidentally polluted

```bash
git -C fork260506-<name> diff --stat HEAD     # tracked-file modifications
git -C fork260506-<name> status --short       # plus untracked
```

If you see tracked-file modifications you did not deliberately make, revert with `git -C fork260506-<name> checkout -- <path>`.

### Force a clean sub-repo (drop everything, tracked + untracked, except gitignored)

```bash
git -C fork260506-<name> reset --hard
git -C fork260506-<name> clean -fd            # ⚠ destroys untracked files; use with care
```

> Avoid `clean -fdx` unless you really want to nuke gitignored caches like `node_modules/` and `go.sum`; rebuilding those is expensive.

---

## 4. Anti-patterns to refuse

If you (or a script) would do any of the following, **stop and ask the user first**:

| Anti-pattern | Why it's wrong |
|---|---|
| `git add fork260506-foo/some/file && git commit` | Bypasses workspace `.gitignore`; pollutes workspace history with content the workspace doesn't own |
| `cd fork260506-foo && git commit -m "fix in workspace"` without explicit user authorization | Changes the fork's own history; that's a fork-side decision, not a workspace-side one |
| `cd fork260506-foo && git push` | Same as above, but worse — propagates to the fork's remote |
| Editing a sub-repo file to "improve" the workspace stack, then leaving it dirty | Fragile; the next person/agent inherits an undocumented patch |
| Adding a `fork260506-foo/...` path to a workspace `git add -A` | The `.gitignore` already prevents it, but **don't try to override** |

---

## 5. Sub-repo entry points (for orientation)

| Sub-repo | Entry point | Build / run |
|---|---|---|
| `fork260506-go-admin` | `main.go` | `go run -tags sqlite3 main.go server` (sqlite) or `... server` with mysql DSN |
| `fork260506-go-admin-ui` | `src/main.js` (Vue app) | `npm install --legacy-peer-deps && npm run dev` (port from `process.env.port`, default 9527) |
| `fork260506-go-admin-doc` | `.dumirc.ts` | `pnpm install && pnpm dev` (dumi 2, default port 8000 — clashes with backend; override) |
| `fork260506-go-admin-core` | (library — no entry) | `go test ./...` for verification |
| `fork260506-gorm-adapter` | (library — no entry) | `go test ./...` |
| `fork260506-redis-watcher` | (library — no entry) | `go test ./...` |
| `fork260506-redisqueue` | (library — no entry) | `go test ./...` |

For full topology (which sub-repo serves which port, which volumes are shared, etc.) see
`docs/superpowers/specs/20260508a_workspace-docker-compose-design.md`.

---

## 6. Relationship to other workspace docs

| Doc | Purpose |
|---|---|
| `CLAUDE.md` | "Read GRAPH_REPORT.md before answering codebase questions." |
| `SUBREPOS.md` *(this file)* | Operational rules: when sub-repos may / may not be touched, how to clean up after a session. |
| `docs/superpowers/specs/20260508a_workspace-docker-compose-design.md` | Workspace-level Docker stack: how the sub-repos are wired together at runtime. |
| `docs/superpowers/plans/20260508a_workspace-docker-compose-impl.md` | Implementation plan that produced the docker-compose stack. |
| `20260509_cdp9229_debug.md` | Lessons from a CDP-driven UI debug session that intentionally violated Rule 4 ("touched a sub-repo file") for verification only — see that file's "Restore" section for what was reverted. |
| `fork260506-go-admin.md`, `fork260506-go-admin-ui.md`, `fork260506-go-admin-core.md`, `fork260506-go-admin-doc.md`, `fork260506-gorm-adapter.md`, `fork260506-redis-watcher.md`, `fork260506-redisqueue.md` | **Per-sub-repo patch logs.** When a deliberate workspace-side patch is applied inside a sub-repo (and per Rule 1 cannot be committed here), the entry goes in the matching file so it can be re-applied or audited later. |
| `fork260506.md`, `fork260506_relationship.md`, `fork260506_update.md`, `fork260506_rust_rewrite_assessment.md`, `fork260506_merge_go_admin_core_assessment.md` | Static analysis / planning docs about the sub-repos as a portfolio. Read-only references; do not commit sub-repo changes inferred from these. |

---

## 7. Revision log

| Date | Change | Author |
|---|---|---|
| 2026-05-09 | Initial version. Codifies the no-commit-into-workspace rule and the post-session restore workflow. | Claude Code |
