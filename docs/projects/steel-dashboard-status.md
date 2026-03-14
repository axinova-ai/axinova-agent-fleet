# Steel Dashboard — Project Status

**Vikunja Project:** trader-ag (ID 29)
**Repos:** axinova-trading-agent-go, axinova-trading-agent-web
**Last updated:** 2026-03-14

## Summary

| Wave | Total | Done | In Review | To-Do | Blocked |
|------|-------|------|-----------|-------|---------|
| 1    | 5     | 5    | 0         | 0     | 0       |
| 2    | 6     | 5    | 0         | 1     | 0       |
| 3    | 6     | 0    | 0         | 6     | gated   |
| 4    | 6     | 0    | 0         | 6     | gated   |
| 5    | 8     | 0    | 0         | 8     | gated   |
| 6    | 2     | 0    | 0         | 2     | gated   |
| 7    | 1     | 0    | 0         | 1     | gated   |
| 8    | 1     | 0    | 0         | 1     | gated   |
| **Total** | **35** | **11** | **0** | **24** | |

## Wave 1 — Foundation (COMPLETE)

| Task | Title | Status | PR | Model |
|------|-------|--------|----|-------|
| T-01 (#235) | Create migration 0004_steel_dashboard | Done | go#25 merged | codex-exec/gpt-5.4 |
| T-04 (#233) | Scaffold Python steel adapter service | Done | go#30 merged | codex-exec/gpt-5.4 |
| T-08 (#234) | Define Go steel domain models and DTOs | Done | go#29 merged | codex-exec/gpt-5.4 |
| T-13 (#236) | Add steel config section to Koanf | Done | go#31 merged | codex-exec/gpt-5.4 |
| T-22 (#232) | Add steel i18n messages (en + zh) | Done | web#40 merged | codex-exec/gpt-5.4 |

## Wave 2 — Data Layer + Adapter Endpoints (5/6 done, 1 waiting for agent)

| Task | Title | Status | PR | Model | Notes |
|------|-------|--------|----|-------|-------|
| T-05 (#239) | Implement adapter quotes endpoint | Done | go#32 merged | codex-exec/gpt-5.4 | Also implemented daily-bars |
| T-06 (#237) | Implement adapter daily-bars endpoint | Done | — | — | Covered by T-05 PR |
| T-23 (#238) | Create steel API client + Pinia store | Done | web#41 merged | codex-exec/gpt-5.4 | |
| T-02 (#240) | Write sqlc queries for steel tables | Done | go#33 merged | codex-exec/gpt-5.4 | Rerouted x3, succeeded attempt 4. Merged 2026-03-14. |
| T-09 (#242) | MarketDataProvider interface + HTTP client | Done | go#34 merged | codex-exec/gpt-5.4 | Rerouted x3, succeeded attempt 4. Merged 2026-03-14. |
| T-07 (#241) | Implement adapter news endpoint | **To-Do** | — | — | Description restored. Waiting for agent pickup. |

## Wave 3 — Store Layer + Vue Components (GATED)

| Task | Title | Priority | Notes |
|------|-------|----------|-------|
| T-03 (#244) | Add steel methods to Store interface + PostgresStore | 3 | Depends on T-02 (sqlc) |
| T-16 (#246) | Implement job scheduler framework | 3 | New package |
| T-24 (#243) | InstrumentTabs + PriceCards Vue components | 0 | Needs priority |
| T-25 (#248) | TrendChart component (ECharts) | 2 | |
| T-26 (#245) | NewsList Vue component | 2 | |
| T-27 (#247) | SignalCard Vue component | 2 | |

## Wave 4 — Service Logic + Dashboard Assembly

| Task | Title | Priority | Notes |
|------|-------|----------|-------|
| T-10 (#251) | Steel service — quote + trend logic | 3 | |
| T-11 (#254) | Steel signal computation | 3 | |
| T-12 (#250) | Steel service — news logic | 3 | |
| T-28 (#253) | Assemble SteelDashboardView + route | 3 | |
| T-30 (#252) | Unit tests — provider response parsing | 2 | |
| T-33 (#249) | Add Python adapter to Docker Compose | 2 | |

## Wave 5 — Jobs + API Handlers + Tests

| Task | Title | Priority | Notes |
|------|-------|----------|-------|
| T-14 (#262) | Chi v5 route handlers for steel API | 3 | |
| T-17 (#256) | Quote refresh scheduled job | 3 | |
| T-18 (#260) | Daily bar backfill job | 3 | |
| T-19 (#257) | News ingestion job | 3 | |
| T-20 (#258) | Signal compute job | 3 | |
| T-21 (#259) | Retention cleanup job | 2 | |
| T-29 (#261) | Unit tests — signal computation | 2 | |
| T-32 (#255) | Frontend tests — steel dashboard | 2 | |

## Wave 6 — Wiring + CI

| Task | Title | Priority | Notes |
|------|-------|----------|-------|
| T-15 (#265) | Wire steel routes into main router | 4 | Founder-only |
| T-34 (#266) | Update CI pipeline for steel module | 5 | Founder-only (needs workflow PAT) |

## Wave 7 — Integration Tests

| Task | Title | Priority | Notes |
|------|-------|----------|-------|
| T-31 (#263) | Integration tests — steel API endpoints | 3 | |

## Wave 8 — Rollout

| Task | Title | Priority | Notes |
|------|-------|----------|-------|
| T-35 (#264) | Internal rollout + monitoring | 5 | Founder-only |

## Closed PRs (pre-wave-gate, out of order)

| PR | Task | Reason |
|----|------|--------|
| go#23 | T-14 | Created before wave-gating, wave-5 task |
| go#24 | T-31 | Created before wave-gating, wave-7 task |
| go#26 | T-04 | 300+ files committed, bad scope |
| go#27 | T-34 | Created before wave-gating, wave-6 task |
| go#28 | T-35 | Created before wave-gating, wave-8 task |
| web#37 | T-23 | Created before wave-gating, replaced by web#41 |
| web#38 | T-24 | Created before wave-gating, wave-3 task |
| web#39 | T-28 | Created before wave-gating, wave-4 task |

## Architecture Changes (2026-03-13)

- **Kimi CLI removed from fallback chain.** `codex exec` (gpt-5.4) is the only automated model. Failures escalate directly to Needs Founder.
- **Priority-based routing active.** Priority ≥4 auto-escalates to Needs Founder (no codex exec attempt).
- **Wave-gating active.** Per-prefix wave labels control task pickup order. Only lowest incomplete wave is eligible.
- **Terminology standardized.** `codex exec` = automated agents, Codex CLI = interactive founder tool, Claude Code CLI = interactive founder tool.

## Action Items

- [x] ~~Review and merge go#33 (T-02) and go#34 (T-09)~~ — merged 2026-03-14
- [ ] Monitor T-07 (#241) — description restored, waiting for agent pickup
- [ ] Set missing priorities on T-28 (#253), T-14 (#262), T-31 (#263), T-35 (#264) (currently 0)
- [ ] Bump T-15 (#265) to priority 4 (wiring = founder task)
- [ ] Bump T-34 (#266) to priority 5 (CI = founder, needs workflow PAT)
- [ ] Bump T-35 (#264) to priority 5 (rollout = founder)
- [ ] Once wave-2 merges complete + T-07 done → wave-3 auto-unlocks
