# Cash mobile local implementation

All work remains in /home/ubuntu/tatuzinV2. No deployment or push was performed. Existing dirty changes were retained.

## Scope

Cash workspace uses scoped ProductStockSurface (Tatuzin purple, light/dark); Caixa atual / Movimentações / Histórico navigation. Opening and closing use dedicated scrollable pages with a 48dp minimum footer inside Scaffold-resized body and one SafeArea. Count calculator returns typed integer-cent denomination details. Blank opening/count amounts require input; explicit zero is valid. Inline failures preserve inputs and repeat taps are locked during work.

CashWorkspaceStore stores tenant DB keys in configuracoes: cash.policy, cash.opening:<uuid>, cash.closing:<uuid>, cash.remote:<uuid>, cash.draft:<company>:<operator>:<scope>. Parent integrated company settings/bootstrap cash.policy. Existing sessions without opening metadata retain legacy non-blind behavior. Auto-open helper used by existing purchase/cost flows snapshots policy; sales retain their existing requirement for an open cash session.

SqliteCashRepository.prepareClosure binds UUID and a serialized snapshot of the complete session row and ordered movement rows. commitClosure rechecks in the SQLite transaction, validates count/reason, freezes closing details, appends immutable outbox event, and clears the operator/session draft atomically. Matching committed requests return the prior closure and cannot close a new session. Optional wire fields are omitted when null; local retry request/token are excluded from wire details. Amounts and denomination totals enforce the backend Int32 cent limit.

Imported cash sessions are history-only and cannot become another device's active register; operational projection and snapshot paths both mark these. Local V2 session values survive remote projection echoes. Closed V2 expected/count/difference map from frozen closing metadata even if movement rebuilds later update legacy columns. Blind active cash hides expected and difference, requires reason regardless of count, and shows frozen results only after close. Route and repository action permission checks remain in force.

## Verification

/tmp/tatuzin-flutter-3.41.9/bin/flutter test test/cash_workspace_test.dart --no-pub

12 tests passed: strict blank/zero/limits; stale preview; mandatory difference/blind reason; exact retry without event duplication; changed underlying totals retain frozen close; rollback on injected outbox trigger failure preserves open cash/draft; commit then DB-file reopen and old-preview retry; policy snapshot and durable draft; eight routed small-screen/font1/2/light/dark footer hit tests with keyboard inset and safe area.

Screenshots: build/cash-workspace/close-{360,390}-font{1,2}-{light,dark}.png. Real NotoSans and MaterialIcons loaded. Insets model a keyboard in the widget harness; screenshots do not contain a rendered native keyboard. Production build artifacts are coordinated by parent.

Focused analyzer passed with no issues before final calculator draft refinement; parent runs broader regression and final analysis. Minimal sale inventory fixture gained configuracoes table because cash bootstrap now persists opening metadata.

## Remaining evidence limits

Native Android/iOS process termination and real screen-reader exploration were not executed. SQLite file reopen, aborted transaction, routed footer hit regions and real font screenshots provide local automated evidence.

## Provisional opening follow-up

Automatic openings now append a CREATE cashSession event with top-level awaitingInitialFloatConfirmation:true and the original opening policy snapshot in the same transaction. Existing enqueue delegates to a reusable enqueueInTransaction helper. Confirmation emits explicit false, records accepted denomination/coin breakdown, preserves policy revision, and rejects any later attempt to edit an already confirmed float. Backend coordinates this one-time provisional transition.

Latest focused run: cash_workspace_test.dart + operational_sync_test.dart + cash_financial_coverage_test.dart passed 58/58, including provisional confirmation and calculator dismissal/restoration. A subsequent legacy compatibility regression was added: sessions missing opening metadata keep legacy wire fields (omit both openingDetails and closingDetails) while retaining their local frozen recovery snapshot. That final added case awaits parent's test window.
