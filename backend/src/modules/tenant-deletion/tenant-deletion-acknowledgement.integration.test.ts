import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, it } from "node:test";

import { PrismaClient } from "@prisma/client";

import { resolveIntegrationTestDatabaseConfig } from "../../shared/testing/integration-prisma";
import { TenantDeletionAcknowledgementService } from "./tenant-deletion-acknowledgement.service";

const config = resolveIntegrationTestDatabaseConfig();
const integrationDescribe = config.enabled ? describe : describe.skip;
const suffix = randomUUID();
let client: PrismaClient;
let companyId: string;
let requestId: string;

integrationDescribe(
  "tenant deletion device acknowledgement integration",
  () => {
    before(async () => {
      if (!config.enabled) {
        return;
      }
      client = new PrismaClient({
        datasources: { db: { url: config.databaseUrl } },
      });
      await client.$connect();
      const company = await client.company.create({
        data: {
          name: "Empresa acknowledgement integration",
          legalName: "Empresa acknowledgement integration LTDA",
          slug: `tenant-ack-integration-${suffix}`,
        },
      });
      companyId = company.id;
      const request = await client.tenantDeletionRequest.create({
        data: {
          companyId,
          activeCompanyGuard: companyId,
          status: "FUTURE_PENDING_DELETION",
          requestedCompanyNameSnapshot: company.name,
          source: "integration_test",
          reason: "Validacao isolada do acknowledgement por dispositivo.",
          identityStatus: "VERIFIED",
        },
      });
      requestId = request.id;
      await client.category.create({
        data: {
          companyId,
          localUuid: `category-${suffix}`,
          name: "Categoria preservada",
        },
      });
    });

    after(async () => {
      if (!config.enabled || client == null) {
        return;
      }
      await client.tenantDeletionAuditEvent.deleteMany({
        where: { requestId },
      });
      await client.tenantDeletionDeviceAcknowledgement.deleteMany({
        where: { tenantDeletionRequestId: requestId },
      });
      await client.tenantDeletionRequest.delete({ where: { id: requestId } });
      await client.category.deleteMany({ where: { companyId } });
      await client.company.delete({ where: { id: companyId } });
      await client.$disconnect();
    });

    it("persiste uma vez, audita e preserva Company e dados operacionais", async () => {
      const clientInstanceId = `device-${suffix}`;
      const service = new TenantDeletionAcknowledgementService(
        client as never,
        {
          verify() {
            return {
              purpose: "tenant_pending_deletion_ack",
              requestId,
              companyId,
              clientInstanceId,
            };
          },
        } as never,
      );
      const input = {
        acknowledgementToken: "integration-token-that-is-never-persisted",
        companyId,
        clientInstanceId,
        platform: "android",
        appVersion: "1.0.0",
      };

      const first = await service.acknowledge(input);
      const second = await service.acknowledge(input);

      assert.equal(first.idempotent, false);
      assert.equal(second.idempotent, true);
      assert.equal(
        await client.tenantDeletionDeviceAcknowledgement.count({
          where: { tenantDeletionRequestId: requestId, clientInstanceId },
        }),
        1,
      );
      assert.equal(
        await client.tenantDeletionAuditEvent.count({
          where: { requestId, eventType: "DEVICE_ACKNOWLEDGED" },
        }),
        1,
      );
      const company = await client.company.findUniqueOrThrow({
        where: { id: companyId },
      });
      assert.equal(company.isActive, true);
      assert.equal(
        await client.category.count({ where: { companyId } }),
        1,
      );
      const persisted = await client.tenantDeletionDeviceAcknowledgement
        .findFirstOrThrow({ where: { tenantDeletionRequestId: requestId } });
      assert.equal(
        JSON.stringify(persisted).includes(input.acknowledgementToken),
        false,
      );
    });
  },
);
