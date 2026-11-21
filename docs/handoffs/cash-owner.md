# Cash owner web handoff

Local implementation only, 2026-11-20. No deployment or GitHub write. Production requires a new explicit user authorization.

## Scope and rendering

The existing native Flutter owner panel now presents `/reports/cash` as a managerial view: period/status/search filters, real server aggregate open/closed/difference/sales metrics, compact desktop session table, cards on small viewports and at 200% text, pagination, original closure facts, receipt reconciliation warnings and append-only divergence review. App operation remains in the app; this page has no opening, cash movement or cash closing controls. Existing sale receipt/return/cancellation actions retain their original service contracts.

The route owns vertical scrolling; the cash page is a plain Column. URL query keys `startDate`, `endDate`, `status`, `search`, `page`, `session` restore filters/page/selected detail. Applying filters resets pagination and selection. Closing a selected detail preserves the other query values. Filter dates validate calendar dates in `YYYY-MM-DD` format and chronological order.

Design reused the existing theme, native widgets, OwnerPageIntro/OwnerMetricCard/OwnerSectionCard and adaptive headers. Astryx table-filter build guidance was adapted to native Flutter without introducing React or dependencies. NotoSans and MaterialIcons are explicitly loaded in image evidence tests.

## Contracts consumed

- GET `/owner/reports/cash-sessions`: existing period/summary/items pagination; optional `summary.openSessions`, `closedSessions`, `totalDifferenceCents` are real aggregates over all filtered sessions, never derived from the displayed page. Missing new metrics render unavailable. Sales totals remain labeled sales.
- `summary.receiptBreakdownAvailable` and each session row's same boolean distinguish reconciled payment receipts from pending/unknown ledger data. False shows an explicit synchronization/reconciliation warning. A verified breakdown renders only when availability is true. Cash-specific `byPaymentMethod[].amountCents` maps to the existing model's `totalAmountCents`; no face-value tender calculation is done by the UI.
- GET `/owner/reports/cash-sessions/:id`: existing session/employee/values/movements/sales; optional `openingDetails`, `closingDetails` immutable metadata; `device:{id,name,platform}`; `hasLateMovements`; `divergenceReview`; `divergenceReviewHistory`; `canReview`.
- Closure V2 displays expected/count/difference from `closingDetails` itself, plus operator reason/notes, denomination quantities, coin total, blind flag and policy revision. Opening V2 displays counted balance and policy revision. Legacy absence explicitly says count details and managerial review are unavailable, while preserving original numeric closure fields from the backend. Missing values are never changed to zero to imply a count. No original closure is recalculated because of late movements; a supplied late flag displays an advisory next to original facts.
- POST `/owner/reports/cash-sessions/:id/divergence-review`: `{requestId: UUIDv4,expectedRevision:int,status:'REVIEWED'|'PENDING',justification:string}`. The owner service accepts `{divergenceReview,canReview}` response and refetches detail/list after success. The confirmation dialog retains the exact request body and UUID across uncertain retry, locks reason after the first attempt, validates a nonempty >=3-character reason, and explicitly reloads on 409 instead of automatically retrying. Reopen applies only to the review state; the session remains closed. Button visibility uses server `canReview`, session closure and nonzero original difference. A frontend role never grants write access.
- GET `/owner/company`: `cashBlindClosureEnabled` (default false), `cashPolicyRevision` (default 0), `canManageCashPolicy` (default false). The Company page shows the current policy with an adaptive switch disabled unless the actual server permission allows it.
- PATCH `/owner/receipt-settings`: `{cashBlindClosureEnabled:boolean}` after confirmation. Company data is refetched after success. The UI explains new openings after device policy refresh, preservation of existing session policy, and legacy-device limitations; it does not claim complete operator secrecy.

## Verification and evidence

Focused tests: `owner_web/test/owner_cash_test.dart` covers 360/390/768/1280/1440 widths, 100% and 200% text, real aggregate-vs-page counts, original V2 metadata, legacy unavailable state, server review denial, justification validation, retained UUID and request body across retries, explicit 409 recovery, URL restoration, policy permission/confirmation, loading/empty/403 states. Native screenshots are generated at `owner_web/build/cash-review/cash-<width>-scale-<1|2>.png`.

The existing `owner_web/test/owner_web_test.dart` additionally exercises the actual `ownerRouterProvider` + OwnerShellScaffold cash route in all five widths at both font scales, navigating a filtered deep link with selected detail and closing it while preserving search. Images include the actual shell at top, session list, original V2 closure and audit confirmation dialog positions: `owner_web/build/phase2-owner/cash-route-<width>-scale-<1|2>-<top|list|detail|audit>.png`. Fixtures are confined to tests/local evidence.

Verified results: focused suite 19/19; actual owner route/shell suite 10/10.

Commands: `/tmp/tatuzin-flutter-3.41.9/bin/flutter test --no-pub test/owner_cash_test.dart`; `/tmp/tatuzin-flutter-3.41.9/bin/flutter test --no-pub test/owner_web_test.dart --plain-name 'real owner cash route'`; `/tmp/tatuzin-flutter-3.41.9/bin/flutter analyze --no-pub` (run inside owner_web).

## Limits

The owner view reports only synchronized backend data. Legacy sessions cannot supply V2 denomination/operator explanations that were never recorded. Ledger reconciliation availability and late arrival flags depend on backend evidence. Session sales detail is explicitly labeled partial when `sales.total > sales.items.length`; the existing detail endpoint returns a fixed first sales page. No fabricated financial conclusion is inferred from that page. No production environment or live financial data was used in image tests.

## Final execution and freeze

Owner source frozen after final route captures. Commands actually executed inside owner_web:

- `flutter test --no-pub test/owner_cash_test.dart --reporter expanded`: exit 0, 19 tests passed (`/tmp/owner-cash-test.log`). Includes real HTTP method/path/body/Bearer assertions for policy PATCH `/owner/receipt-settings` and audit POST, plus reconciled receipt amount parsing.
- `flutter test --no-pub test/owner_web_test.dart --plain-name 'real owner cash route' --reporter expanded`: exit 0, 10 tests passed (`/tmp/owner-cash-route.log`); actual production router + shell at five widths × two font scales; top/list/detail/audit PNGs generated.
- `flutter analyze --no-pub`: exit 0, no issues (`/tmp/owner-cash-analyze.log`). This final analyzer ran before adding the final audit screenshots to the already passing route tests; root will run full owner suite and analyzer after source freeze.
- `git diff --check -- owner_web docs/handoffs/cash-owner.md`: exit 0.

No additional Flutter command will be started by this agent after freeze. Root owns the final full suite/build decision.

## Authorized decision update: cloud company cash, independent per employee

The subsequent explicit user decision supersedes the earlier per-device model for new sessions. Owner web now begins with **Caixa geral da empresa**, the cloud consolidation, followed by **Caixas por funcionário**. One employee shares the same cash workspace across participating devices. Another employee has an independent workspace. This page performs no opening, movements, closing or employee reconfirmation.

Current cloud data is independent of the historical period/status/search filters, which remain under **Histórico de sessões**. No legacy floats are merged into employee workspaces by this frontend. Legacy availability is explicitly identified with a warning that old session funds are not added to company cash. Existing V2 opening/closing metadata, the root correction `openingDetails.countedAmountCents`, and `openingAwaitingConfirmation` remain intact.

New real endpoint: GET `/owner/reports/cash-workspace`, protected by existing owner report read permissions. Response:

- `version:3`, `summary:{openEmployees,pendingEmployees,totalExpectedBalanceCents,confirmedCountedBalanceCents,legacySessions}`, `legacySessionsPresent`.
- `employees:[{employee:{id,name},activeSessionId,sessionIds,status,expectedBalanceCents,countedBalanceCents,differenceCents,participants:[{deviceId,name,lastAckGeneration}],pendingReasons,closureRequest,canReview,...}]`.
- `totalExpectedBalanceCents` includes current OPEN/PENDING_SYNC/REVIEW_REQUIRED workspaces only; it excludes old CLOSED balances. `confirmedCountedBalanceCents` represents the latest confirmed closed count per employee. The UI displays these as separate amounts and never subtracts one from the other or recomputes them from visible rows.
- Employee statuses are `OPEN`, `PENDING_SYNC`, `REVIEW_REQUIRED`, `CLOSED`. Pending declared counts remain labeled **conferência pendente** and never become confirmed because a device sent an offline proposal. Only CLOSED rows show a confirmed difference. Missing amounts remain unavailable, never a fabricated zero.
- `AWAITING_PARTICIPANT_SYNC` explains that participant devices still need to synchronize. `BALANCE_CHANGED_RECONFIRM_REQUIRED` explains that the responsible employee must reconfirm in the app after a changed balance. Participant acknowledgements compare the server-provided `lastAckGeneration` with `closureRequest.generation`; the UI does not infer completeness by counting devices locally.
- Session consultation uses `activeSessionId`, falling back to canonical `sessionIds[0]`, and opens the existing session detail in the URL. The viewport moves to the detail when it loads. Workspace pending status adds an explicit not-confirmed notice and suppresses the divergence audit controls. The backend independently sets detail `canReview:false` until actual closure.
- Owner/ADMIN report read authorization permits managerial amounts independently of audit write permission. `canReview` never hides authorized managerial balances and never grants any operational capability. It controls the existing immutable divergence review only.

New files: `owner_web/lib/src/features/reports/presentation/owner_cash_workspace_section.dart` and test-only `owner_web/test/fixtures/cash_workspace_fixture.dart`. Typed workspace models, the authenticated GET method and scope/refresh-aware provider integrate with existing owner architecture.

## V3 sale financial operation gate

V3 sale DTOs provide `canCancel:false`, `canReturn:false`, and `actionUnavailableReason:'CASH_V3_REFUND_REQUIRES_OPERATOR_APP'`. The owner page consumes that exact reason and says **Faça a operação no app com funcionário autorizado.** Receipt consultation remains available. It never enables an operation based on a local role. Legacy actions continue to use their existing server capabilities. The backend independently returns HTTP 409 with the same code for V3 cancel/return attempts.

## Final V3 verification and new source freeze

The latest source freeze supersedes the earlier freeze statement. Actual commands executed inside owner_web with `/tmp/tatuzin-flutter-3.41.9/bin/flutter`:

- `flutter test --no-pub test/owner_cash_test.dart --reporter expanded`: **exit 0, 24 tests passed**, log `/tmp/owner-workspace-tests.log`. Includes the two root-added opening count regressions, authenticated HTTP GET path `/api/owner/reports/cash-workspace`, existing policy/audit HTTP assertions, multi-employee grouping data, provisional count/participant acknowledgement state, visibility independent of audit write capability, V3 operation gate, and preserved legacy/audit cases.
- `flutter test --no-pub test/owner_web_test.dart --plain-name 'real owner cash route' --reporter expanded`: **exit 0, 10 tests passed**, log `/tmp/owner-workspace-routes.log`. Actual production router and shell at 360/390/768/1280/1440 pixels, each at 100% and 200% text, with real NotoSans/MaterialIcons. Tests open participants, consult a pending employee session through the actual modal/card action, verify the pending session URL and absence of premature audit controls, and preserve original history/audit navigation.
- `flutter analyze --no-pub`: **exit 0, no issues**, log `/tmp/owner-workspace-analyze.log`.
- `git diff --check -- owner_web docs/handoffs/cash-owner.md`: **exit 0**.

Native actual-shell evidence now includes `owner_web/build/phase2-owner/cash-workspace-<width>-scale-<1|2>-employees.png` and `...-participants.png`, plus refreshed existing `cash-route-...-top/list/detail/audit.png` captures. The 360px/200% participant view and 1440px employee table were visually reviewed. All fixtures remain exclusively in local tests. No production access, deployment or GitHub write occurred.

Real-router tests caught and resolved two concrete issues: participant dialogs now close the root dialog navigator instead of popping the nested shell route, and each employee/sale ExpansionTile has its own PageStorageKey, preventing expansion booleans from colliding with route scroll offsets during query/session navigation. Vertical scrolling remains owned by the existing route.

Owner source is frozen again. No further Flutter command will be started by this agent; root owns full-suite verification and any subsequent build decision.
