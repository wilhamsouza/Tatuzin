-- Preserve existing platform-admin READ access without granting operational writes.
-- Existing explicit inactive grants are deliberately left untouched.
WITH inserted AS (
  INSERT INTO "AdminUserPermission" (id, "actorUserId", "permissionKey", scope, "scopeId", "isActive", "createdAt", "updatedAt")
  SELECT md5(u.id || ':' || p.key || ':platform:*'), u.id, p.key, 'platform', '*', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
  FROM "User" u CROSS JOIN (VALUES
    ('admin.overview.read'), ('admin.companies.read'), ('admin.support.read'),
    ('admin.sync.read'), ('admin.billing.read'), ('admin.devices.read'),
    ('admin.usage.read'), ('admin.audit.read')
  ) AS p(key)
  WHERE u."isPlatformAdmin" = true
  ON CONFLICT ("actorUserId", "permissionKey", scope, "scopeId") DO NOTHING
  RETURNING "actorUserId", "permissionKey"
)
INSERT INTO "AdminAuditLog" (id, "actorType", "actorUserId", "actorLabel", action, details, "createdAt")
SELECT md5('admin-platform-read-bootstrap:' || "actorUserId"), 'BOOTSTRAP', NULL, 'SYSTEM_BOOTSTRAP',
  'admin.platform.read-access.migrated',
  jsonb_build_object('targetAdminId', "actorUserId", 'permissions', jsonb_agg("permissionKey"), 'executionPrivilegesAdded', false),
  CURRENT_TIMESTAMP
FROM inserted GROUP BY "actorUserId";
