import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { AppError } from "../../shared/http/app-error";
import { TenantDeletionAcknowledgementService } from "./tenant-deletion-acknowledgement.service";

const validInput = {
  acknowledgementToken: "signed-token-value-that-is-long-enough",
  companyId: "11111111-1111-4111-8111-111111111111",
  clientInstanceId: "device-instance-1",
  deviceLabel: "  Android\u0000 principal  ",
  platform: "android",
  appVersion: "1.0.0",
  acknowledgedAt: "2026-06-12T12:00:00.000Z",
};

const claims = {
  purpose: "tenant_pending_deletion_ack" as const,
  requestId: "22222222-2222-4222-8222-222222222222",
  companyId: validInput.companyId,
  clientInstanceId: validInput.clientInstanceId,
};

describe("tenant deletion device acknowledgement", () => {
  it("cria acknowledgement e auditoria sanitizada sem alterar Company", async () => {
    let acknowledgementData: Record<string, unknown> | null = null;
    let auditData: Record<string, unknown> | null = null;
    const service = new TenantDeletionAcknowledgementService(
      {
        tenantDeletionRequest: {
          async findFirst() {
            return { id: claims.requestId, companyId: claims.companyId };
          },
        },
        tenantDeletionDeviceAcknowledgement: {
          async findUnique() {
            return null;
          },
        },
        async $transaction(callback: (tx: unknown) => Promise<unknown>) {
          return callback({
            tenantDeletionDeviceAcknowledgement: {
              async create({ data }: { data: Record<string, unknown> }) {
                acknowledgementData = data;
                return {
                  id: "ack-1",
                  acknowledgedAt: new Date("2026-06-12T12:00:00.000Z"),
                  createdAt: new Date("2026-06-12T12:00:01.000Z"),
                };
              },
            },
            tenantDeletionAuditEvent: {
              async create({ data }: { data: Record<string, unknown> }) {
                auditData = data;
                return { id: "audit-1" };
              },
            },
          });
        },
      } as never,
      { verify: () => claims } as never,
    );

    const result = await service.acknowledge(validInput);
    const savedAcknowledgement =
      acknowledgementData as Record<string, unknown> | null;
    const savedAudit = auditData as Record<string, unknown> | null;

    assert.equal(result.acknowledged, true);
    assert.equal(result.idempotent, false);
    assert.equal(savedAcknowledgement?.deviceLabel, "Android principal");
    assert.equal(
      JSON.stringify(savedAcknowledgement).includes(
        validInput.acknowledgementToken,
      ),
      false,
    );
    assert.equal(savedAudit?.eventType, "DEVICE_ACKNOWLEDGED");
    assert.match(
      String(
        (savedAudit?.metadataJson as Record<string, unknown>)
          .clientInstanceIdMasked,
      ),
      /^sha256:[a-f0-9]{12}$/,
    );
    assert.equal(
      JSON.stringify(savedAudit).includes(validInput.clientInstanceId),
      false,
    );
  });

  it("e idempotente por request e clientInstanceId", async () => {
    const existing = {
      id: "ack-existing",
      acknowledgedAt: new Date("2026-06-12T12:00:00.000Z"),
      createdAt: new Date("2026-06-12T12:00:00.000Z"),
    };
    const service = new TenantDeletionAcknowledgementService(
      {
        tenantDeletionRequest: {
          async findFirst() {
            return { id: claims.requestId, companyId: claims.companyId };
          },
        },
        tenantDeletionDeviceAcknowledgement: {
          async findUnique() {
            return existing;
          },
        },
        async $transaction() {
          throw { code: "P2002" };
        },
      } as never,
      { verify: () => claims } as never,
    );

    const result = await service.acknowledge(validInput);

    assert.equal(result.idempotent, true);
    assert.equal(result.acknowledgementId, existing.id);
  });

  it("nao aceita tenant sem solicitacao ativa e nao inicia transacao", async () => {
    let transactionCalls = 0;
    const service = new TenantDeletionAcknowledgementService(
      {
        tenantDeletionRequest: {
          async findFirst() {
            return null;
          },
        },
        tenantDeletionDeviceAcknowledgement: {
          async findUnique() {
            return null;
          },
        },
        async $transaction() {
          transactionCalls++;
        },
      } as never,
      { verify: () => claims } as never,
    );

    await assert.rejects(
      service.acknowledge(validInput),
      (error: unknown) =>
        error instanceof AppError &&
        error.code === "TENANT_DELETION_ACK_NOT_ACCEPTED",
    );
    assert.equal(transactionCalls, 0);
  });

  it("rejeita divergencia entre capability e payload", async () => {
    const service = new TenantDeletionAcknowledgementService(
      {} as never,
      { verify: () => claims } as never,
    );

    await assert.rejects(
      service.acknowledge({
        ...validInput,
        clientInstanceId: "different-device",
      }),
      (error: unknown) =>
        error instanceof AppError &&
        error.code === "TENANT_DELETION_ACK_NOT_ACCEPTED",
    );
  });
});
