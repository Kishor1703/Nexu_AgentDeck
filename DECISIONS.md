# DECISIONS

1. **What counts as "untrusted" (A7 vs A1 "SAFE runs automatically").**
   Unclear which results are untrusted and whether SAFE tools may auto-run after one.
   I treat *every* tool result as untrusted (even get_tasks, whose titles are user/agent text).
   A step proposed right after a result is flagged: WRITE then needs the PIN, DANGER already does.
   SAFE tools still auto-run (A1) but carry the warning flag in the timeline and audit log.
   Why: blocking read-only tools would break normal runs; reads cannot change anything.

2. **Retry counting (A2).** "Retry once; a second failure ends the run" can mean per run or per step.
   I count *consecutive* failures: one retry per model step; a valid output resets the counter.
   Why: with the 15% faulty mode, a per-run limit would kill long runs for unrelated glitches.

3. **Reset demo data vs. an undeletable audit log (G vs E), and budget counting (A3).**
   Reset clears tasks, outbox, wallet and the on-screen runs but never the audit log; the reset is itself logged.
   A call counts toward the budget when it is proposed (before approval), so a 6th proposal halts the run
   with "Budget reached" and a second DANGER proposal halts even if the first was rejected is impossible
   (a rejection ends the run).

4. **PIN creation.** No PIN may be hardcoded, so the first time a PIN is needed the user creates one
   (stored as salted hash); afterwards it is verified.
