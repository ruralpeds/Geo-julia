# Gap Analysis Schema for [Repo Name]

**Repository**: `ruralpeds/[repo-name]`
**Last Updated**: 2026-04-23
**Scope**: Defines gap analysis rules specific to this repository

---

## Gap ID Naming Convention

```
GAP-NNN    (per-repo numbering, zero-padded)

Examples:
- GAP-001   (first gap in this repo)
- GAP-042   (42nd gap)
- GAP-999   (max 999 gaps per repo; if you hit this, time to archive old ones!)
```

**Alternative (organization-wide):**
```
GAP-[REPO_PREFIX]-NNN

Example: GAP-SCI-001, GAP-STATS-042, GAP-NEO-003

[We recommend per-repo numbering for simplicity]
```

---

## Status Update Cadence

- **Minimum**: Weekly (e.g., Monday morning sprint check-in)
- **Ideal**: On every PR merge (update status if relevant)
- **Never**: More than 2 weeks without a status update

**Enforcement**: Monthly review (Timothy checks all repos' gaps for staleness)

---

## Ownership Rules

| Priority | Requirement |
|----------|-------------|
| **P0 (Blocker)** | MUST have an owner + target date within 30 days |
| **P1 (Critical)** | MUST have an owner + target date within 90 days |
| **P2 (High)** | Should have owner; target date recommended |
| **P3 (Medium)** | Owner optional; no target date required |
| **P4 (Low)** | Owner optional; no target date required |

**Unassigned Rule**: If a P0/P1 gap has been unassigned for >2 weeks, it shows up in compliance reports. Review and assign or deprioritize.

---

## Cross-Repo Dependencies

### How to Reference Other Gaps

**Same organization, different repo:**
```markdown
**Blocked By**: GAP-008 (repo: ruralpeds/rust-sci-core)
```

**With full GitHub link:**
```markdown
**Blocked By**: [GAP-008](https://github.com/ruralpeds/rust-sci-core/blob/main/.gap-analysis/GAP_ANALYSIS.md#gap-008-feature-name)
```

### Dependency Resolution

If GAP-A blocks GAP-B (in different repos), both repos should document the relationship:

**In repo A's gap:**
```markdown
**Blocking Issues**: GAP-B (repo: ruralpeds/other-repo) — waiting on our completion
```

**In repo B's gap:**
```markdown
**Blocked By**: GAP-A (repo: ruralpeds/rust-sci-core) — unblock when A is merged
```

---

## Examples of Good Gaps ✅

**Specific, measurable, actionable:**

1. **CDC/WHO percentile interpolation**
   ```
   "Implement QuadraticSpline interpolation for CDC/WHO growth reference 
   tables (0–19 years). Validate against NCHS published z-scores. Test 
   edge cases: extreme growth velocity, malnutrition."
   ```

2. **Rosenbrock implicit solver**
   ```
   "Add Rosenbrock34 to sci-ode for medium-stiffness ODEs. Benchmark against 
   Hairer test suite (E1–E5). Implement W-formulation with dual-number 
   Jacobians. GMRES linear solver integration."
   ```

3. **Competing risks analysis**
   ```
   "Kaplan-Meier with competing risks: Aalen-Johansen estimator, Gray's test, 
   cumulative incidence plotting. Validate against cmprsk R package (1% tolerance). 
   Unit tests: 3-event systems, 100-patient simulations."
   ```

---

## Examples of Bad Gaps ❌

**Vague, unmeasurable, not actionable:**

1. **"Improve performance"**
   - ❌ No metrics (latency? throughput? memory?)
   - ✅ Rewrite: "Reduce ODE solver step time from 5ms to 1ms (20K steps/sec target)"

2. **"Refactor the codebase"**
   - ❌ Too broad; unclear what "refactor" means
   - ✅ Rewrite: "Split `solver.rs` into `solvers/rk4.rs`, `solvers/tr_bdf2.rs`, etc. (modular architecture)"

3. **"Research machine learning"**
   - ❌ Exploratory; no deliverable
   - ✅ Rewrite: "Prototype neural ODE solver for comparison with classical methods; write blog post with benchmarks"

4. **"Fix bugs"**
   - ❌ Which bugs? What's the scope?
   - ✅ Rewrite: "Fix #456: edge case in percentile calculation when patient height > 95th percentile; add unit test"

---

## Acceptance Criteria Guidelines

Acceptance criteria should be **specific, verifiable, and testable**.

### Good ✅

```markdown
- [ ] Framingham trait defined in src/cardiovascular/framingham.rs
- [ ] Implementation validated against 10 published Framingham cohorts
- [ ] Unit tests: 50+ cases covering edge cases (BMI extremes, age < 30, post-MI)
- [ ] Benchmarks: <1ms per calculation (1M iterations)
- [ ] Documentation with examples and references
```

### Bad ❌

```markdown
- [ ] Implement Framingham calculator
- [ ] Tests pass
- [ ] Documentation done
```

**Why?** The "good" version is verifiable. The "bad" version is vague.

---

## Priority Justification

Before assigning a priority, ask:

1. **P0 (Blocker)?** → Does this block a release? Fail compliance? Break existing features?
2. **P1 (Critical)?** → High impact? Planned for next 1–3 months? Customer-blocking?
3. **P2 (High)?** → Important? Scheduled in roadmap? But not blocking?
4. **P3 (Medium)?** → Backlog-level. Will happen eventually.
5. **P4 (Low)?** → Exploratory. Might never happen.

**Example priority justification:**
```markdown
**Priority**: P1 (Critical)

**Justification**: Needed for Phase 2 of PedNeoSim.jl (neonatal digital twin). 
Blocks clinical validation studies scheduled for Q3 2026. No workaround available 
(Kaplan-Meier alone insufficient for competing endpoints).
```

---

## Implementation Timeline Guidelines

### Target Completion Dates

- **P0**: Must have date ≤30 days away
- **P1**: Should have date ≤90 days away
- **P2**: Can be vague ("Q3 2026" is fine)
- **P3–P4**: Optional (can be "TBD")

**If date is overdue**: Update the gap with why (blocked, deprioritized) and new target.

### How to Estimate

1. **Complexity**: How many lines of code? How many components?
2. **Testing**: How thorough? (unit + integration + edge cases?)
3. **Review**: How much code review + feedback cycles?
4. **Blockers**: Any dependencies? External libraries?

**Conservative estimate**: Add 30% buffer for review cycles.

---

## Blocking vs. Blocked By

### Blocking Issues
```markdown
**Blocking Issues**: #456 (regression in percentile calculation), #789 (missing test)

→ These are GitHub issues that prevent THIS gap from being worked on.
→ Typically bugs or missing dependencies in the same repo.
```

### Blocked By
```markdown
**Blocked By**: GAP-005 (sci-probability interval sampling)

→ This gap is waiting on another gap to complete.
→ Could be same repo or different repo.
```

---

## Status Transitions

```
NOT STARTED ──→ BACKLOG ──→ IN PROGRESS ──→ IN REVIEW ──→ COMPLETED
                              ↓
                           BLOCKED ────────────→ (unblock) ──→ IN PROGRESS
                              
ARCHIVED ←──────── (decide not to do)
```

**Valid transitions:**
- Not Started → Backlog
- Backlog → In Progress
- In Progress → In Review
- In Progress → Blocked
- Blocked → In Progress
- In Review → Completed
- Any → Archived

**Invalid transitions** (avoid):
- Backlog → Completed (must go through In Progress)
- Blocked → Completed directly (unblock first, then complete)

---

## Definition of "Completed"

A gap is **Completed** when:

1. ✅ All acceptance criteria are met (via code review + tests)
2. ✅ PR is merged to `main`
3. ✅ Tested in production (or staging if not yet released)
4. ✅ Documentation is updated
5. ✅ Gap is moved to "Completed Gaps" section in GAP_ANALYSIS.md

**Not** "completed" if:
- ❌ Still in draft PR
- ❌ Passing tests but not merged
- ❌ Merged but not documented
- ❌ Merged but acceptance criteria only partially met

---

## Archival Rules

### When to Archive

- Gap was open for >6 months with no progress → Deprioritize or archive
- Decision made not to implement → Archive with reason
- Superseded by better approach → Archive with reference to replacement gap
- Out of scope for repo → Archive with explanation

### Archive Format

```markdown
## Archive (Decided Not To Do)

### 🗑️ GAP-XXX: [Feature name]
**Status**: Archived
**Archived Date**: 2026-06-15
**Reason**: [Specific reason]

**Example reasons:**
- "Deprioritized in Q3 roadmap. Revisit in 2027 if customer demand increases."
- "Superseded by GAP-042 (better approach discovered)."
- "Out of scope; belongs in separate repo."
- "Technical evaluation showed ROI insufficient; cost > benefit."
```

### Retention

- Keep archived gaps for institutional memory (shows decision rationale)
- Once a repo has >15 archived gaps, consider moving to separate `ARCHIVE.md` file

---

## Compliance & Auditing

### What Gets Audited

- ✅ All gaps have status (never blank)
- ✅ Status values are valid enums (not free text)
- ✅ P0/P1 gaps have owners + target dates
- ✅ Gap IDs are unique within repo
- ✅ Target dates are YYYY-MM-DD format
- ✅ Completed gaps have PR numbers and notes

### Who Audits

- **Automated**: GitHub Actions (weekly `gap-analysis-validate.yml`)
- **Manual**: Timothy Hartzog (monthly review, spot checks)

### What Happens If Non-Compliant

1. GitHub issue created: "Compliance Report: [Repo] missing gap analysis" (or has syntax errors)
2. Repo has **1 week** to fix
3. If not fixed: escalates to org meeting

---

## Tips for This Repo

[Add repo-specific guidance here. Examples:]

### rust-sci-core

- **Gap IDs**: Sequential across 15+ crates (not per-crate); keep gaps in `main` GAP_ANALYSIS.md
- **Ownership**: Each crate should have at least one P1 gap with named owner
- **Testing**: All sci-* gaps must include benchmarks vs. reference implementations (Hairer, SUNDIALS, SciPy)
- **WASM**: Any WASM-capable crate (sci-ode, sci-stats) should have WASM binding gaps

### modeling (textbook generation)

- **Gap IDs**: Correspond to chapter numbers (GAP-001 = Chapter 1, etc.) where applicable
- **Ownership**: Each textbook (ODEs, ABM, Probability) should have chapter draft owners
- **Acceptance Criteria**: Include "Quarto builds cleanly" and "all math renders"
- **Review**: Each chapter moved to "Completed" after Timothy + collaborator review

### theology-analysis (theology research)

- **Gap IDs**: Free-form; can be topical (e.g., GAP-Covenant, GAP-Theodicy) or chronological
- **Ownership**: Always assigned (Timothy + collaborators)
- **Completion**: Includes link to GitHub blob (specific commit/line numbers of theological analysis)

---

## Questions?

Refer to:
- **Organization standard**: [`.gap-analysis/README.md`](../../.gap-analysis/README.md) in `ruralpeds/.github`
- **Archived 2026-04 standards & quick reference**: [`docs/archive/2026-04-gap-analysis/`](../../docs/archive/2026-04-gap-analysis/)
- **Workflow automation**: `.github/workflows/gap-analysis-*.yml` in `ruralpeds/.github`

---

## Change Log

| Date | Change | Who |
|------|--------|-----|
| 2026-04-23 | Initial schema created | Timothy |
| 2026-04-28 | Updated references after standards/quick-reference were archived | Claude (claude/update-gap-analysis-6bUTw) |
