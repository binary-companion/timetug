# TimeTug audit remediation results

Updated 2026-10-11. The [audit](2026-09-26-program-analysis.md) and [handoff plan](../superpowers/plans/2026-09-26-audit-remediation-handoff.md) began at commit `7f96bb8`. Tasks 1–10, 12–15 and 17–19 were merged in [PR #51](https://github.com/darkarena1/timetug/pull/51). This closeout finishes the measured deduplication work (Task 11), makes Linux CI blocking after successful same-code runs (Task 16), and records final evidence (Task 20). Later provider, distribution and website changes remain in current `master`; this work was based on `9b94777`, not the old uncommitted checkout.

Microsoft sign-in now requests read-only scopes by the owner's later decision in [ADR 0017](../decisions/0017-microsoft-read-only-scopes.md) and [PR #49](https://github.com/darkarena1/timetug/pull/49). The connector library's write implementation remains. The owner confirmed the read-only policy for this closeout; no Microsoft scope or capability change is part of it.

## Code and review

`DuplicateResolver` now indexes equal content keys and overlapping timed intervals, evaluates distant blocking pairs only when a group merge needs them, and uses constant-time candidate-ID membership. Its public result and ordering remain checked against the frozen pre-optimization resolver across boundary, lesson, randomized, transitive-block and duplicate-ID fixtures. The benchmark runner accepts a shape and count for focused reruns while retaining the full matrix by default.

DeepSeek was the primary reviewer. Its resolver review found one proposed dense-case concern but refuted its own fixture; a targeted final candidate-list review found no mismatch. Its CI review caught a stale “allowed to fail” comment, and its agent-guide review identified five confirmed documentation gaps plus one uncertain index-instruction gap. Those comments and the linked runbook, architecture and index/architecture-check instructions were corrected. No DeepSeek finding was accepted without checking it against the repository.

The root `AGENTS.md` had regrown to **2,070 words / 15,865 bytes** on current `master`. It is now **420 words / 3,528 bytes**; detailed procedures remain reachable through the current architecture, development guide, operations runbook and task skills. This is a measured reduction in default reading size, not a measured token-cost or wall-time reduction.

## Measurements and verification

Release-build benchmark on macOS/arm64 with deterministic synthetic events, one warmup and five timed runs per case. The baseline and changed resolver used the same `9b94777` code; only the benchmark's case selector was copied into the temporary baseline checkout. Times are medians in milliseconds.

| Input | Baseline | Changed | Ratio |
|---|---:|---:|---:|
| Sparse, 1,000 events | 686.494 | 2.806 | 245× faster |
| Sparse, 5,000 events | 18,503.169 | 15.128 | 1,223× faster |
| Dense, 500 events | 8,481.206 | 875.002 | 9.7× faster |
| Duplicate-heavy, 5,000 events | 30,406.681 | 5,609.773 | 5.4× faster |

The duplicate-heavy case produced 1,250 cards in both versions. The 5,000-event dense case was not completed: it produces a quadratic manual-candidate result under the current public API and is resource-heavy even after pair search is indexed. No speedup or bounded-memory claim is made for that case.

The synthetic Google and Microsoft connector tests each request exactly 20 calendars and assert a peak of no more than four simultaneous event reads; this is test-harness evidence, not a count from live accounts. The previous one-second UI structural timer was replaced by policy-driven updates, but an idle-hour rebuild count was not measured. Agent token counts and tool-call savings were not captured and are not estimated.

`verify.sh all` passed locally on macOS after the code, workflow, benchmark and guide changes: **24 checks, zero failures and zero skips** (40 seconds, run `build/verify/20261011T141737Z-59717`). Two completed `master` CI runs, [38138250241](https://github.com/darkarena1/timetug/actions/runs/38138250241) and [38138726121](https://github.com/darkarena1/timetug/actions/runs/38138726121), passed `core-linux`; the job is therefore required in this change.

The hosted [TimeTug site](https://timetug.binarycompanion.com/) returned HTTP 200 with the configured Content-Security-Policy on 2026-10-11, and the latest relevant Firebase merge workflow [succeeded](https://github.com/darkarena1/timetug/actions/runs/38138080155). Live provider writes, interactive macOS UI checks, release signing and a new deployment are separate from this local/CI remediation. They have not been claimed as verified here.
