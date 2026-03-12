# Lesson Learned: MCP Server Stale Binary — Vikunja Description Wipe

**Date:** 2026-03-12
**Impact:** All `vikunja_update_task` MCP calls wiped task descriptions for 3 days (Mar 9–12)
**Severity:** High — lost descriptions on 8+ Sprint 5 tasks, caused repeated manual data restoration

---

## Root Cause

The MCP server binary at `/usr/local/bin/axinova-mcp-server` was **never rebuilt** after the GET-then-POST fix was committed.

| What | When |
|------|------|
| Binary built (stale) | Mar 9 03:09 |
| GET-then-POST fix committed (`95cfc40`) | Mar 9 17:39 |
| DoneSet/PrioritySet fix committed (`e66601e`) | Mar 10 17:18 |
| Bug discovered & binary rebuilt | Mar 12 11:12 |

The stale binary did a **direct POST** to Vikunja's `/api/v1/tasks/{id}` endpoint. Vikunja replaces ALL fields on POST — any omitted field resets to its zero value. So calling `update_task(task_id=X, done=true)` sent `{"done": true}` without `title`, `description`, etc., wiping them all.

## Secondary Issue: macOS Code Signing

After rebuilding, `cp` to `/usr/local/bin/` invalidated the ad-hoc code signature. macOS killed the binary with `SIGKILL (Code Signature Invalid)` on every launch. The MCP server showed "Failed to connect" in `claude mcp list`.

**Fix:** Build to `/tmp/`, sign with `codesign -s -`, then `mv` (not `cp`) to `/usr/local/bin/`.

## Prevention

### Rule: Always rebuild after MCP server code changes

```bash
cd axinova-mcp-server-go
go build -o /tmp/axinova-mcp-server ./cmd/server
codesign -s - -f /tmp/axinova-mcp-server
sudo mv /tmp/axinova-mcp-server /usr/local/bin/axinova-mcp-server
# Then restart Claude Code to pick up the new binary
```

### Checklist

- [ ] After any commit to `axinova-mcp-server-go`, rebuild the binary
- [ ] After rebuilding, **sign** the binary (`codesign -s -`)
- [ ] Use `mv` not `cp` to install (preserves signature)
- [ ] Restart Claude Code session to reconnect MCP
- [ ] Test with a round-trip: update a field, verify other fields preserved

## How the Fix Works

The `UpdateTask()` function in `internal/clients/vikunja/client.go` now:

1. **GET** the existing task (preserves all current field values)
2. **Merge** only the explicitly-provided fields (using `DoneSet`/`PrioritySet` flags for zero-value-ambiguous fields)
3. **POST** the complete merged payload back

This ensures unmodified fields are never lost.

## Affected Tasks

Sprint 5 tasks that had descriptions wiped: #172, #173, #174, #175, #177, #178, #179, #180, #181
