# SilverBullet Wiki SOP

Standard operating procedure for agents and engineers creating or updating wiki pages in the Axinova SilverBullet instance.

---

## Mandatory Frontmatter

Every page **must** begin with a YAML frontmatter block:

```yaml
---
title: <Page Title>
tags: [<domain>, <type>, ...]
owner: platform-engineering
reviewed: YYYY-MM-DD
status: active
type: <hub|overview|runbook|workflow|inventory>
---
```

**Fields:**

| Field | Required | Values |
|-------|----------|--------|
| `title` | Yes | Human-readable, matches the page heading |
| `tags` | Yes | At least 2; see Tag Taxonomy below |
| `owner` | Yes | `platform-engineering` for shared pages |
| `reviewed` | Yes | ISO date of last review (`YYYY-MM-DD`) |
| `status` | Yes | `active`, `draft`, `deprecated` |
| `type` | Yes | See page types below |

---

## Page Types

| Type | Description | Example |
|------|-------------|---------|
| `hub` | Top-level index with navigation | `index` |
| `overview` | High-level summary of a domain | `Agent Fleet/Overview` |
| `runbook` | Step-by-step operational procedure | `Agent Fleet/Runbooks/PR Health Workflow` |
| `workflow` | Automated process documentation | CI/CD pipeline docs |
| `inventory` | Reference list (hosts, repos, ports) | port tables |

---

## Tag Taxonomy

Use tags from these domains (combine as needed):

| Domain | Tags |
|--------|------|
| System | `agent-fleet`, `infrastructure`, `repos`, `ops` |
| Purpose | `runbook`, `overview`, `onboarding`, `inventory` |
| Tech | `go`, `docker-compose`, `ci`, `vpn`, `postgres` |
| Process | `dependencies`, `security`, `pr`, `deployment` |

---

## Page Naming Convention

- Use `/` for hierarchy: `Agent Fleet/Runbooks/PR Health Workflow`
- Title case for proper nouns, lowercase for common words
- No numeric prefixes (avoid `01-index.md` — use clean names)
- Keep names short but unambiguous

**Structure:**

```
index                              ← workspace hub
Agent Fleet/Overview               ← domain overview
Agent Fleet/Runbooks/<Name>        ← agent runbooks
Infrastructure/Overview            ← infra reference
Repos/Overview                     ← repo inventory
Operations/<Topic>                 ← operational processes
```

---

## Linking

Always use `[[wiki-links]]` instead of plain text or URLs for internal pages:

```markdown
# Good
See [[Agent Fleet/Overview]] for fleet details.
Handled by [[Agent Fleet/Runbooks/PR Health Workflow]].

# Bad
See Agent Fleet/Overview for fleet details.
See https://wiki.axinova-internal.xyz/Agent%20Fleet/Overview
```

Every page should have a **Related Pages** section at the bottom linking to 2–5 related pages.

---

## Structure Template

```markdown
---
title: <Title>
tags: [<domain>, <type>]
owner: platform-engineering
reviewed: YYYY-MM-DD
status: active
type: <type>
---

# <Title>
> One-line description of what this page covers.

## <Main Section>
...content...

## Related Pages
- [[Page One]]
- [[Page Two]]
```

For **runbooks**, use numbered steps or a flow table:

```markdown
## Flow
| Step | Trigger | Action | Limit |
|------|---------|--------|-------|
| ... | ... | ... | ... |
```

For **overviews**, use tables instead of dense paragraphs:

```markdown
## Services
| Name | Port | Purpose |
|------|------|---------|
| ... | ... | ... |
```

---

## Update Process

1. **Edit** the page content
2. **Update** `reviewed:` date to today
3. **Verify** all `[[wiki-links]]` resolve (no broken links)
4. **Check** tags still match the content
5. For significant changes, add a brief note at the bottom under `## Changelog` (optional)

---

## When to Create a New Page

Create a new page when:
- A topic needs more than ~50 lines in an existing page
- A runbook covers a distinct procedure
- A new service, repo, or system is added

Do **not** create pages for:
- Single-use notes (use task comments in Vikunja instead)
- Duplicating content already on another page (link instead)

---

## MCP Access for Agents

Agents use the `mcp__axinova-tools__silverbullet_*` tools:

```
silverbullet_list_pages       # discover existing pages
silverbullet_get_page         # read a page before editing
silverbullet_create_page      # create new page
silverbullet_update_page      # update existing page (always read first)
silverbullet_search_pages     # find relevant pages
```

**Agent workflow:**
1. `search_pages` to check if a page already exists
2. `get_page` to read current content before updating
3. `update_page` with full content (not partial — SilverBullet replaces the whole page)
4. Update `reviewed:` date in frontmatter

---

## Review Cadence

| Page Type | Review Frequency |
|-----------|-----------------|
| `hub` | Monthly |
| `overview` | After major infra/fleet changes |
| `runbook` | After each incident or process change |
| `inventory` | When adding/removing services or repos |

---

## Reference

- Reviewed: 2026-03-02
- Codex review: gpt-5.3-codex suggestions applied 2026-03-02
- Kimi K2.5 improvement pass: 2026-03-02
