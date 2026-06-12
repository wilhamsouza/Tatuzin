import type { RequestHandler } from "express";
import { Router } from "express";

import { asyncHandler } from "../../shared/http/async-handler";
import { createRateLimit } from "../../shared/http/rate-limit";
import { validateBody } from "../../shared/http/validate";
import {
  tenantDeletionAcknowledgementSchema,
  type TenantDeletionAcknowledgementInput,
} from "./tenant-deletion-acknowledgement.schemas";
import { TenantDeletionAcknowledgementService } from "./tenant-deletion-acknowledgement.service";

type PublicTenantDeletionRouterDependencies = {
  acknowledgementService?: Pick<
    TenantDeletionAcknowledgementService,
    "acknowledge"
  >;
  rateLimit?: RequestHandler;
};

const acknowledgementRateLimit = createRateLimit({
  name: "tenant_deletion_device_acknowledgement",
  windowMs: 60_000,
  max: 12,
  message:
    "Muitas tentativas de acknowledgement. Aguarde um instante e tente novamente.",
  code: "TENANT_DELETION_ACK_RATE_LIMITED",
  keyGenerator(request) {
    const clientInstanceId =
      request.body != null &&
      typeof request.body.clientInstanceId === "string"
        ? request.body.clientInstanceId.trim()
        : "unknown-client";
    return `${request.ip}:${clientInstanceId}`;
  },
});

export function createPublicTenantDeletionRouter(
  dependencies: PublicTenantDeletionRouterDependencies = {},
) {
  const router = Router();
  const service =
    dependencies.acknowledgementService ??
    new TenantDeletionAcknowledgementService();

  router.post(
    "/acknowledge-pending-deletion",
    dependencies.rateLimit ?? acknowledgementRateLimit,
    validateBody(tenantDeletionAcknowledgementSchema),
    asyncHandler(async (request, response) => {
      const payload = await service.acknowledge(
        request.body as TenantDeletionAcknowledgementInput,
      );
      response.status(200).json(payload);
    }),
  );

  return router;
}

export const publicTenantDeletionRouter = createPublicTenantDeletionRouter();
