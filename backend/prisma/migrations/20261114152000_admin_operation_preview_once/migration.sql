-- Each controlled preview can be consumed once, even with distinct client retry keys.
CREATE UNIQUE INDEX "SupportActionExecution_platform_preview_once"
ON "SupportActionExecution" ("dryRunAuditEventId")
WHERE "actionType" IN ('access.block','access.reactivate','license.extend','license.suspend','license.reactivate','billing.refresh','device.diagnostics');
