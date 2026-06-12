import { createHash } from "node:crypto";

import type { PrismaClient } from "@prisma/client";
import jwt from "jsonwebtoken";

import { env } from "../../config/env";
import { prisma } from "../../database/prisma";
import { AppError } from "../../shared/http/app-error";
import type { TenantDeletionAcknowledgementInput } from "./tenant-deletion-acknowledgement.schemas";
import { tenantPendingDeletionStatus } from "./tenant-lifecycle.service";

const acknowledgementAudience = "tenant-deletion-device-acknowledgement";
const acknowledgementIssuer = "tatuzin-api";
const acknowledgementPurpose = "tenant_pending_deletion_ack";

type AcknowledgementClaims = {
  purpose: typeof acknowledgementPurpose;
  requestId: string;
  companyId: string;
  clientInstanceId: string;
};

type AcknowledgementClient = Pick<
  PrismaClient,
  | "$transaction"
  | "tenantDeletionRequest"
  | "tenantDeletionDeviceAcknowledgement"
>;

export type TenantDeletionDeviceContext = {
  clientInstanceId?: string | null;
  deviceLabel?: string | null;
  platform?: string | null;
  appVersion?: string | null;
};

export class TenantDeletionAcknowledgementTokenService {
  issue(input: {
    requestId: string;
    companyId: string;
    clientInstanceId: string;
  }) {
    return jwt.sign(
      {
        purpose: acknowledgementPurpose,
        requestId: input.requestId,
        companyId: input.companyId,
        clientInstanceId: input.clientInstanceId,
      } satisfies AcknowledgementClaims,
      env.JWT_SECRET,
      {
        algorithm: "HS256",
        audience: acknowledgementAudience,
        expiresIn: "90d",
        issuer: acknowledgementIssuer,
        subject: input.clientInstanceId,
      },
    );
  }

  verify(token: string): AcknowledgementClaims {
    try {
      const decoded = jwt.verify(token, env.JWT_SECRET, {
        algorithms: ["HS256"],
        audience: acknowledgementAudience,
        issuer: acknowledgementIssuer,
      });
      if (
        typeof decoded === "string" ||
        decoded.purpose !== acknowledgementPurpose ||
        typeof decoded.requestId !== "string" ||
        typeof decoded.companyId !== "string" ||
        typeof decoded.clientInstanceId !== "string"
      ) {
        throw new Error("invalid acknowledgement claims");
      }
      return {
        purpose: acknowledgementPurpose,
        requestId: decoded.requestId,
        companyId: decoded.companyId,
        clientInstanceId: decoded.clientInstanceId,
      };
    } catch {
      throw acknowledgementRejected();
    }
  }
}

export class TenantDeletionAcknowledgementService {
  constructor(
    private readonly client: AcknowledgementClient =
      prisma as AcknowledgementClient,
    private readonly tokenService = new TenantDeletionAcknowledgementTokenService(),
  ) {}

  async acknowledge(input: TenantDeletionAcknowledgementInput) {
    const claims = this.tokenService.verify(input.acknowledgementToken);
    if (
      claims.companyId !== input.companyId ||
      claims.clientInstanceId !== input.clientInstanceId
    ) {
      throw acknowledgementRejected();
    }

    const request = await this.client.tenantDeletionRequest.findFirst({
      where: {
        id: claims.requestId,
        companyId: claims.companyId,
        status: tenantPendingDeletionStatus,
        activeCompanyGuard: claims.companyId,
      },
      select: {
        id: true,
        companyId: true,
      },
    });
    if (request == null) {
      throw acknowledgementRejected();
    }

    const acknowledgedAt = normalizeAcknowledgedAt(input.acknowledgedAt);
    try {
      const acknowledgement = await this.client.$transaction(async (tx) => {
        const created = await tx.tenantDeletionDeviceAcknowledgement.create({
          data: {
            tenantDeletionRequestId: request.id,
            companyId: request.companyId,
            clientInstanceId: claims.clientInstanceId,
            deviceLabel: sanitizeClientMetadata(input.deviceLabel),
            platform: sanitizeClientMetadata(input.platform),
            appVersion: sanitizeClientMetadata(input.appVersion),
            acknowledgedAt,
            source: "mobile_app",
            metadataJson: {
              localTimestampProvided: input.acknowledgedAt != null,
            },
          },
        });
        await tx.tenantDeletionAuditEvent.create({
          data: {
            requestId: request.id,
            companyId: request.companyId,
            eventType: "DEVICE_ACKNOWLEDGED",
            reason: "Dispositivo informou recebimento do bloqueio operacional.",
            metadataJson: {
              clientInstanceIdMasked: maskIdentifier(claims.clientInstanceId),
              platform: sanitizeClientMetadata(input.platform),
              appVersion: sanitizeClientMetadata(input.appVersion),
              source: "mobile_app",
            },
          },
        });
        return created;
      });
      return serializeAcknowledgement(acknowledgement, false);
    } catch (error) {
      if (!isUniqueConstraint(error)) {
        throw error;
      }
      const existing =
        await this.client.tenantDeletionDeviceAcknowledgement.findUnique({
          where: {
            tenantDeletionRequestId_clientInstanceId: {
              tenantDeletionRequestId: request.id,
              clientInstanceId: claims.clientInstanceId,
            },
          },
        });
      if (existing == null) {
        throw error;
      }
      return serializeAcknowledgement(existing, true);
    }
  }
}

function acknowledgementRejected() {
  return new AppError(
    "Nao foi possivel registrar o acknowledgement informado.",
    409,
    "TENANT_DELETION_ACK_NOT_ACCEPTED",
  );
}

function sanitizeClientMetadata(value: string | null | undefined) {
  const normalized = value
    ?.replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  return normalized == null || normalized.length === 0 ? null : normalized;
}

function normalizeAcknowledgedAt(value: string | undefined) {
  if (value == null) {
    return new Date();
  }
  const parsed = new Date(value);
  const now = Date.now();
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.getTime() > now + 5 * 60_000 ||
    parsed.getTime() < now - 30 * 24 * 60 * 60_000
  ) {
    return new Date();
  }
  return parsed;
}

function maskIdentifier(value: string) {
  const digest = createHash("sha256").update(value).digest("hex").slice(0, 12);
  return `sha256:${digest}`;
}

function isUniqueConstraint(error: unknown) {
  return (
    typeof error === "object" &&
    error != null &&
    "code" in error &&
    error.code === "P2002"
  );
}

function serializeAcknowledgement(
  acknowledgement: {
    id: string;
    acknowledgedAt: Date;
    createdAt: Date;
  },
  idempotent: boolean,
) {
  return {
    ok: true,
    acknowledged: true,
    idempotent,
    acknowledgementId: acknowledgement.id,
    acknowledgedAt: acknowledgement.acknowledgedAt.toISOString(),
    createdAt: acknowledgement.createdAt.toISOString(),
  };
}
