part of 'migrations.dart';

// Versions 1-37 are published history and stay frozen in migrations.dart.
// Add future migration steps here so new work can be grouped without renumbering
// or reordering already distributed versions.
const List<MigrationStep> futureMigrationSteps = <MigrationStep>[
  MigrationStep(version: 38, up: _createVersion38Schema),
];

Future<void> _createVersion38Schema(DatabaseExecutor db) async {
  await db.execute(
    'ALTER TABLE ${TableNames.vendas} ADD COLUMN customer_assignment_locked INTEGER NOT NULL DEFAULT 0',
  );
  await db.execute(
    'ALTER TABLE ${TableNames.vendas} ADD COLUMN customer_assignment_revision INTEGER NOT NULL DEFAULT 0',
  );
  await db.execute(
    'ALTER TABLE ${TableNames.vendas} ADD COLUMN seller_remote_user_id TEXT',
  );
  await db.execute('''CREATE TABLE sale_customer_assignments (
    event_id TEXT PRIMARY KEY,
    sale_id INTEGER NOT NULL REFERENCES ${TableNames.vendas}(id),
    previous_client_id INTEGER,
    client_id INTEGER NOT NULL REFERENCES ${TableNames.clientes}(id),
    expected_revision INTEGER NOT NULL,
    actor_user_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    occurred_at TEXT NOT NULL
  )''');
  await db.execute(
    'CREATE INDEX idx_sale_customer_assignments_sale ON sale_customer_assignments(sale_id, expected_revision)',
  );
}
