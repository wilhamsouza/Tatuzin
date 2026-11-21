# Cash backend local handoff — 2026-11-20

Scope: local workspace only. No production database/config/service changes, deployments or GitHub pushes were performed.

## Delivered contract

- Additive migration `backend/prisma/migrations/20261120090000_cash_workspace/migration.sql`: Company `cashBlindClosureEnabled=false`, `cashPolicyRevision=0`; independent append-only `CashDivergenceReviewEvent` table with tenant/session/request/revision uniqueness and FK constraints.
- App context `company`, GET/PATCH `/api/app/company/settings` (and the existing owner PATCH `/api/owner/receipt-settings`) response `company`, and GET `/api/owner/company` expose policy fields. PATCH accepts optional `cashBlindClosureEnabled`; policy revision advances atomically only for a changed value. Owner company adds `canManageCashPolicy` / `canUpdateCashPolicy` actual OWNER/ADMIN write grants.
- Sync operational CashSession keeps optional `openingDetails` / `closingDetails` exactly as agreed V2 shapes in payload. Count cents strict integers, denomination sum exact, closing difference exact, opening/session/policy match, reason mandatory for divergence and for every blind close. Snapshot from cached opening policy is retained even after company policy changes. Legacy events still accepted and marked version 1; no retroactive V2 upgrade/audit.
- First V2 creation binds authenticated device. V2 cannot transfer devices; opens serialize on physical device; another device can have independent same-operator session. Closed replay identical produces duplicate without writes; changed closing metadata conflicts. Opening policy immutable. Explicit top-level `awaitingInitialFloatConfirmation:true` marks an auto-open count zero as provisional. Exactly one true→false UPDATE/upsert may replace count/denominations/coins while both stored/requested session remain open, on the same authenticated device and original policy. Row lock/refetch serializes concurrent confirmations. Then count is immutable; false→true, policy changes, and pending closure are rejected. Identical confirmation replay keeps the same count. Late V2 movement events occurring within the original open interval are accepted without changing the closure snapshot; movements occurring after closure conflict.
- Detail includes `openingAwaitingConfirmation` (saved provisional flag: true before count confirmation, false after; null for legacy), `openingDetails`, `closingDetails`, `divergenceReview`, `divergenceReviewHistory`, `canReview`, `device`, `hasLateMovements`. List session rows include device and late indicator. `device` null or `{id,name,platform}` from actual CompanyDevice. Late indicator null for legacy/open, boolean for closed V2 based server ingestion after frozen closure materialization; original balances remain unchanged.
- GET `/api/owner/reports/cash-sessions/:id/divergence-review` returns `{divergenceReview}`. POST same URL accepts `{requestId: UUID, expectedRevision: nonnegative integer, status:'PENDING'|'REVIEWED', justification:required trimmed string max2000}` and returns `{divergenceReview,canReview}`.
- `divergenceReview` null for legacy/open/no-difference; otherwise `{sessionId,revision,status,comments:[{requestId,revision,status,justification,authorId,authorName,createdAt}]}`. Revision 0 is implicit pending; history contains only actual submitted events. Endpoint requires tenant scope and reports.advanced; append additionally effective OWNER/MANAGER plus employees.manage. Same request id/content/author retries are idempotent, changed reuse or stale revision 409. Session row lock serializes revisions; original closure payload is never rewritten by audit.

## Financial report correction

Owner report payment breakdown now derives actual receipt movement ledger (`venda`, `recebimento_fiado`, `cancelamento` plus canonical aliases), excludes manual supply/withdrawal from receipt totals, and does not use the face value of fiado orders as money received. It never adds sale face values on top of movements. All filtered rows feed summary before pagination. Summary includes `openSessions`, `closedSessions` (normalized status), and `totalDifferenceCents` (original differences, closed sessions only). Removed prior 50-movement truncation and the discovered 250-session source cap.

Summary and session rows carry `receiptBreakdownAvailable` and `receiptBreakdownUnavailableReason`. Missing/unreconciled immediate receipt ledger, unknown tender, or admin return/cancel action without allocated receipt evidence yield unavailable and empty payment breakdown, rather than guessed cash/Pix/card totals. Existing sale/cancel/admin-return financial mutation rules were preserved; root separately fixed mobile fiado cancellation tender allocation.

## Verification

Scoped command (explicit disposable DB only):

`DATABASE_URL=postgresql://cash_test:isolated-cash-test-only@127.0.0.1:55442/tatuzin_cash_test JWT_SECRET=cash-disposable-test-secret APP_ENV=test NODE_ENV=test node_modules/.bin/tsx --test src/modules/cash/cash-divergence-review.integration.test.ts src/modules/cash/cash-receipt-summary.test.ts src/modules/sync/materializers/cash-session-v2.test.ts`

17 tests passed: immutable V2 count and close checks, blind zero-difference reason, tampered totals, device conflict and no legacy retrofit; tenant/role/read/manage gates, append history, idempotency, conflict and concurrent revisions; concurrent opens on physical device, independent second device, allowed pre-close late movement and rejected post-close movement, unchanged closure; concurrent repeated policy setting no extra revision; Pix/cash/partial fiado/cancellation receipt totals, no double count, unavailable fallbacks and mixed session methods; 251 filtered sessions with pageSize 1 verify counts and closed-only differences beyond the old 250-session cap; unit and real DB tests for synced automatic provisional zero-count opening, one concurrent successful confirmation, rejected subsequent count/policy edits and false→true rearming.

Prisma schema validate and TypeScript `--noEmit` passed. Standard build emission encountered preexisting EACCES in `dist/modules/tenant-deletion`; isolated real build `tsc -p tsconfig.json --outDir /tmp/tatuzin-cash-backend-build` passed. Parent owns complete existing regression suite on disposable DB 55442 and financial mobile regressions.

## Rollback

Keep additive columns and audit table/history. Set company blind policy off and roll clients/server back when authorized; older clients omit metadata and retain legacy acceptance. Do not delete or rewrite original closure snapshots or submitted review events. No destructive down migration is proposed. Production rollout still requires new user authorization.

## Self review

Applied ECC database-migrations, security-review and agent-self-evaluation guidance. Accuracy 4/5 (17 scoped tests, schema/type/build pass; full existing regressions delegated to root). Completeness 4/5 (requested backend delivered; legacy receipt history without session/tender source remains explicitly unavailable). Clarity 4/5 (exact field contract documented; new code follows compact existing service patterns). Actionability 4/5 (migration and local build ready; production requires separate authorization). Conciseness 4/5 (handoff deliberately includes exact contract and limitations for integration). Overall 4.0/5. Main follow-up: root complete regression suite and owner UI unavailable-state verification; user should find the conservative unavailable receipt status preferable to a guessed financial balance.

# Authorized replacement: V3 employee cash workspace

This section supersedes the device-owned V2 model for NEW V3 cash. Existing V1/V2 sessions and their tested behavior remain legacy-compatible and explicitly identified. No production actions occurred.

## Persistence and ownership

- `20261120100000_employee_cash_workspace`: CashSession workspaceVersion/revision/generation; partial unique active `(companyId,userId)` for V3; registered participants; revisioned immutable-original-count closure requests; per-device acknowledgements.
- `20261120101000_employee_cash_blind_count`: nullable localExpectedBalanceCents, so blind clients never fabricate an expected balance.
- `20261120102000_cash_workspace_deferred_device_keys`: deferred NO ACTION participant/ack device foreign keys. Deleting a participant device alone remains forbidden; tenant cascade deletion succeeds atomically.
- All three applied only to disposable PostgreSQL `127.0.0.1:55442/tatuzin_cash_test` (55 total local migrations).
- Employee identity always authenticated User.id / CashSession.userId, never EmployeeProfile.id or client-supplied employeeId. One canonical active V3 cash per company/user across devices. Open on a second device attaches participation and preserves the first float exactly once. V3 initialization requires online open/join; cached registered participation permits operational offline writes.

## Stable application API

All responses are `{version:3,session:null|Session,legacySessionsPresent:boolean}`. POST open additionally returns `joinedExisting:boolean` explicitly.

- GET `/api/app/cash/workspace`: read own current V3 cash, else latest closed; does not implicitly join a device.
- POST `/api/app/cash/sessions/open`: `{requestId:UUID,openingBalanceCents:int,denominations?:[{valueCents,quantity}],coinsCents?:int}`. Creates or atomically attaches the current authenticated employee's canonical session. Same original open request/content retries return that original session; changed reuse conflicts.
- POST `/api/app/cash/sessions/:uuid/join`: `{requestId:UUID}`. Online registration of this authenticated physical device to its employee's existing active canonical cash.
- POST `/api/app/cash/sessions/:uuid/closure-requests`: `{requestId:UUID,expectedRevision:int,countedBalanceCents:int,localExpectedBalanceCents?:int|null,reason?:string,notes?:string,denominations?,coinsCents?}`. A proposal only: never closes immediately. Local expected required in normal mode; omitted/null accepted in blind mode.
- POST `/api/app/cash/sessions/:uuid/closure-requests/:requestId/ack`: `{generation:int,revision:int,drained:true}`. Client must fence local writes, push/pull/drain, then acknowledge exact generation/revision. Server rejects its own actor's unresolved PENDING/FAILED/CONFLICT operational events. Events from another trusted user on a shared physical device do not block an unrelated employee's cash.
- POST `/api/app/cash/sessions/:uuid/closure-requests/:requestId/reconfirm`: same count body with NEW requestId and current expectedRevision. Prior request is SUPERSEDED; original count remains retained as its own record.

Session DTO: `{closingDetails:null|immutableOriginalClosingDetails,uuid,id,employeeId,openedAt,closedAt,status:'OPEN'|'PENDING_SYNC'|'REVIEW_REQUIRED'|'CLOSED',revision,openingBalanceCents,expectedBalanceCents:int|null,blindClosureEnabled,policyRevision,currentDeviceJoined:boolean,confirmedMovementUuids:string[],participants:[{deviceId,name,lastAckGeneration:int|null}],closureRequest:null|{requestId,generation,revision,status,countedBalanceCents,expectedBalanceCents:int|null,differenceCents:int|null,reason}}`.

`currentDeviceJoined` is derived from the authenticated server device and registered participants. `confirmedMovementUuids` are CashEvent.localUuid identities included in the SAME locked read as expected/revision. The app reconciles its retained local cash deltas by exact UUID coverage, avoiding double count or loss when a GET crosses a queued push acknowledgement. Expected/count difference is redacted on blind app responses until actual CLOSED; manager reports with reports.advanced retain read access independently of audit write permission.

## Barrier and finance

A closure remains pending until EVERY registered device acknowledges the same generation/revision after drain. Every accepted V3 operational write (cash movement, sale and sale-related payment/receipt/order/stock events) locks the canonical session, validates authenticated user/participant and invalidates prior acknowledgements within the same transaction. New participant registration also advances closure generation. A changed physical expected balance sets REVIEW_REQUIRED; a stale offline count proposal sets REVIEW_REQUIRED and requires a new count request. An expected revision ahead of the server conflicts. Blind review is driven by ledger changes/revision, never by count-vs-expected (no difference oracle); blind reason always required. Normal nonzero difference requires reason before entering the final pending generation.

The final acknowledgement acquires the same session row lock as operational writes. It either freezes final closingDetails and original count after all current acknowledgements, or a concurrent late write invalidates the generation. A write accepted before finalization cannot disappear behind a stale frozen close. New V3 writes after CLOSED reject, even with old client timestamps; existing immutable domain duplicates may replay. New operations use a newly opened own employee cash.

Physical expected = initial float once + signed cash receipt/fiado receipt movements + supplies + signed adjustments - absolute withdrawals/sangria. Pix/card movements never change physical cash. No whole fiado sale face value is counted as a receipt. Both actual negative withdrawal payloads and defensive positive withdrawal aliases normalize safely. Refund CashMovement must bind the authorized CURRENT own cash; original sale references do not imply permission to write the original closed cash. Existing classic financial audit records remain compatible because they do not mutate the physical V3 ledger. Owner V3 return/cancel APIs without allocated current-cash ledger reject 409 `CASH_V3_REFUND_REQUIRES_OPERATOR_APP`; sale DTO canCancel/canReturn=false and actionUnavailableReason carries that code. Legacy actions retain their existing rules.

## Manager workspace

GET `/api/owner/reports/cash-workspace` requires existing owner-panel/report read grants. Returns `{version:3,summary,employees,legacySessionsPresent}`.

Summary: `openEmployees`, `pendingEmployees`, `totalExpectedBalanceCents` (ACTIVE employee cash only, excludes historical closed turns), `confirmedCountedBalanceCents` (latest closed cash only for employees without an active register), `legacySessions`; scopes explicitly returned as expectedScope ACTIVE_EMPLOYEE_REGISTERS and confirmedCountedScope LATEST_CLOSED_PER_EMPLOYEE_WITHOUT_ACTIVE_REGISTER.

Each employee: `{employee:{id,name},activeSessionId:null|id,sessionUuid,sessionIds:[selectedCanonicalSessionId],status,expectedBalanceCents,countedBalanceCents:null|int,differenceCents:null|int,participants,pendingReasons:string[],revision,closureRequest,canReview}`. pendingReasons is AWAITING_PARTICIPANT_SYNC or BALANCE_CHANGED_RECONFIRM_REQUIRED. `lastAckGeneration` only proves this device acknowledged that generation, compared to the current closure generation. The endpoint selects current/latest sessions in SQL and batch-loads participant/closure/ledger rows; it does not load all historical turns or perform per-employee queries. Full history remains in existing employee-filtered cash-session reports. Detail cashWorkspaceVersion identifies V3; pending V3 canReview=false. Existing audit writes become available only after true final closure and preserve original count.

## New evidence

`cash-workspace-v3.integration.test.ts` currently passes 12 real DB cases: canonical same employee across devices, opening retry/conflict/single float, trusted actor/tenant/participant gates across direct and sale-related writes, stale client snapshot cannot rewrite float, cash/Pix/fiado/withdrawal actual payload math, all-participant barrier, late writes/reconfirm/final freeze, closed-new-write rejection and duplicate replay, blind no-expected/no-difference oracle, independent manager report read, stale offline review, legacy separation, truthful joined flag, V3 owner bypass 409/action flags, shared-device other-user event isolation, five final-ack/write races, exact UUID/balance/revision snapshot coverage during concurrent pushes, own unresolved event gate and device-deletion barrier protection. Prior 17 Cash V2/audit tests still pass (27 tests in the combined run before the final two new V3 tests; V3 12/12 passed afterward). Parent owns the separate real HTTP two-device/token suite and broader regression.

Rollback remains additive: preserve V3 session/participant/count/ack history; do not silently downgrade an active V3 cash to legacy or force-finalize a pending request. Client/server rollout and any production migration/deployment require new explicit user authorization.

V3 app workspace `session.closingDetails` is null until actual CLOSED, then exposes the entire saved immutable original snapshot (including winning notes/denominations/coins/reason). Devices must use that server snapshot and never merge losing local proposal fields. Real DB coverage verifies another participant reads the exact winning full snapshot.
