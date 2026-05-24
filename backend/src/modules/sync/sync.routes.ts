import {
  Router,
  type NextFunction,
  type Request,
  type Response,
} from "express";

import { AppError } from "../../shared/http/app-error";
import { requireAppContext } from "../../shared/http/auth-middleware";
import { asyncHandler } from "../../shared/http/async-handler";
import { validateBody, validateQuery } from "../../shared/http/validate";
import { SyncConflictService } from "./sync-conflict.service";
import { SyncEventService } from "./sync-event.service";
import { SyncSupportService } from "./sync-support.service";
import {
  syncSupportCommandCompleteSchema,
  type SyncSupportCommandCompleteInput,
  syncSupportCommandFailSchema,
  type SyncSupportCommandFailInput,
  syncSupportDiagnosticSchema,
  type SyncSupportDiagnosticInput,
  syncConflictQuerySchema,
  syncPullQuerySchema,
  syncResolveConflictSchema,
  type SyncConflictQueryInput,
  type SyncPullQueryInput,
} from "./sync.schemas";

export const syncRouter = Router();

const syncEventService = new SyncEventService();
const syncConflictService = new SyncConflictService();
const syncSupportService = new SyncSupportService();

syncRouter.use(requireAppContext);
syncRouter.use(requireSyncContext);

syncRouter.get(
  "/status",
  asyncHandler(async (request, response) => {
    const payload = await syncEventService.getStatus(request.appContext!);
    response.json(payload);
  }),
);

syncRouter.get(
  "/pull",
  validateQuery(syncPullQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await syncEventService.pull(
      request.appContext!,
      request.query as unknown as SyncPullQueryInput,
    );
    response.json(payload);
  }),
);

syncRouter.post(
  "/push",
  asyncHandler(async (request, response) => {
    const payload = await syncEventService.push(
      request.appContext!,
      request.body,
    );
    response.status(202).json(payload);
  }),
);

syncRouter.post(
  "/diagnostics",
  validateBody(syncSupportDiagnosticSchema),
  asyncHandler(async (request, response) => {
    const payload = await syncSupportService.reportDiagnostic(
      request.appContext!,
      request.body as SyncSupportDiagnosticInput,
    );
    response.json(payload);
  }),
);

syncRouter.get(
  "/support-commands",
  asyncHandler(async (request, response) => {
    const payload = await syncSupportService.pullCommands(request.appContext!);
    response.json(payload);
  }),
);

syncRouter.post(
  "/support-commands/:id/start",
  asyncHandler(async (request, response) => {
    const commandId = readParam(request.params.id);
    const payload = await syncSupportService.startCommand(
      request.appContext!,
      commandId,
    );
    response.json(payload);
  }),
);

syncRouter.post(
  "/support-commands/:id/complete",
  validateBody(syncSupportCommandCompleteSchema),
  asyncHandler(async (request, response) => {
    const commandId = readParam(request.params.id);
    const payload = await syncSupportService.completeCommand(
      request.appContext!,
      commandId,
      request.body as SyncSupportCommandCompleteInput,
    );
    response.json(payload);
  }),
);

syncRouter.post(
  "/support-commands/:id/fail",
  validateBody(syncSupportCommandFailSchema),
  asyncHandler(async (request, response) => {
    const commandId = readParam(request.params.id);
    const payload = await syncSupportService.failCommand(
      request.appContext!,
      commandId,
      request.body as SyncSupportCommandFailInput,
    );
    response.json(payload);
  }),
);

syncRouter.get(
  "/conflicts",
  validateQuery(syncConflictQuerySchema),
  asyncHandler(async (request, response) => {
    const payload = await syncConflictService.list(
      request.appContext!,
      request.query as unknown as SyncConflictQueryInput,
    );
    response.json(payload);
  }),
);

syncRouter.post(
  "/conflicts/:id/reprocess",
  asyncHandler(async (request, response) => {
    const conflictId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await syncEventService.reprocessConflict(
      request.appContext!,
      conflictId,
    );
    response.json(payload);
  }),
);

syncRouter.post(
  "/conflicts/:id/resolve",
  validateBody(syncResolveConflictSchema),
  asyncHandler(async (request, response) => {
    const conflictId = Array.isArray(request.params.id)
      ? request.params.id[0]
      : request.params.id;
    const payload = await syncConflictService.resolve(
      request.appContext!,
      conflictId,
      request.body,
    );
    response.json(payload);
  }),
);

function readParam(value: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}

function requireSyncContext(
  request: Request,
  _response: Response,
  next: NextFunction,
) {
  const context = request.appContext;
  if (
    context == null ||
    context.company.id.trim().length === 0 ||
    context.user.id.trim().length === 0 ||
    context.clientInstanceId.trim().length === 0 ||
    context.device.status !== "ACTIVE" ||
    context.tenantReady !== true
  ) {
    next(
      new AppError(
        "Contexto completo do app obrigatorio para sincronizar.",
        403,
        "APP_CONTEXT_REQUIRED",
      ),
    );
    return;
  }

  if (!context.license.syncEnabled) {
    next(
      new AppError(
        "A sincronizacao esta desabilitada para esta licenca.",
        403,
        "SYNC_DISABLED",
      ),
    );
    return;
  }

  next();
}
