import { Router } from "express";

import { buildPaginatedResponse } from "../../shared/http/api-response";
import { requireAppContext } from "../../shared/http/auth-middleware";
import { asyncHandler } from "../../shared/http/async-handler";
import { requireFeature } from "../../shared/http/feature-middleware";
import { validateBody, validateQuery } from "../../shared/http/validate";
import { EmployeeActivityService } from "./employee-activity.service";
import { EmployeeCommissionService } from "./employee-commission.service";
import { requireEmployeePermission } from "./employee-permission-middleware";
import {
  employeeActivityQuerySchema,
  type EmployeeActivityQueryInput,
  employeeCommissionSettingsSchema,
  type EmployeeCommissionSettingsInput,
  employeeCreateSchema,
  employeeListQuerySchema,
  type EmployeeListQueryInput,
  employeeUpdateSchema,
} from "./employees.schemas";
import { EmployeesService } from "./employees.service";

const employeesService = new EmployeesService();
const employeeActivityService = new EmployeeActivityService();
const employeeCommissionService = new EmployeeCommissionService();

export const employeesRouter = Router();

employeesRouter.use(requireAppContext, requireFeature("employees"));

employeesRouter.get(
  "/commissions/summary",
  validateQuery(employeeActivityQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as EmployeeActivityQueryInput;
    const result = await employeeCommissionService.summary(
      request.appContext!,
      query,
    );
    response.json(result);
  }),
);

employeesRouter.get(
  "/:id/commission-settings",
  asyncHandler(async (request, response) => {
    const result = await employeeCommissionService.getSettings(
      request.appContext!,
      readParam(request.params.id),
    );
    response.json(result);
  }),
);

employeesRouter.patch(
  "/:id/commission-settings",
  validateBody(employeeCommissionSettingsSchema),
  asyncHandler(async (request, response) => {
    const result = await employeeCommissionService.updateSettings(
      request.appContext!,
      readParam(request.params.id),
      request.body as EmployeeCommissionSettingsInput,
    );
    response.json(result);
  }),
);

employeesRouter.get(
  "/:id/commissions",
  validateQuery(employeeActivityQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as EmployeeActivityQueryInput;
    const result = await employeeCommissionService.detail(
      request.appContext!,
      readParam(request.params.id),
      query,
    );
    response.json(result);
  }),
);

employeesRouter.get(
  "/activity/summary",
  validateQuery(employeeActivityQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as EmployeeActivityQueryInput;
    const result = await employeeActivityService.summary(
      request.appContext!,
      query,
    );
    response.json(result);
  }),
);

employeesRouter.get(
  "/:id/activity",
  validateQuery(employeeActivityQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as EmployeeActivityQueryInput;
    const result = await employeeActivityService.detail(
      request.appContext!,
      readParam(request.params.id),
      query,
    );
    response.json(result);
  }),
);

employeesRouter.use(requireEmployeePermission("employees.manage"));

employeesRouter.get(
  "/",
  validateQuery(employeeListQuerySchema),
  asyncHandler(async (request, response) => {
    const query = request.query as unknown as EmployeeListQueryInput;
    const result = await employeesService.list(request.appContext!, query);
    response.json(
      buildPaginatedResponse({
        items: result.items,
        page: query.page,
        pageSize: query.pageSize,
        total: result.total,
      }),
    );
  }),
);

employeesRouter.get(
  "/:id",
  asyncHandler(async (request, response) => {
    const employee = await employeesService.get(
      request.appContext!,
      readParam(request.params.id),
    );
    response.json({ employee });
  }),
);

employeesRouter.post(
  "/",
  validateBody(employeeCreateSchema),
  asyncHandler(async (request, response) => {
    const employee = await employeesService.create(
      request.appContext!,
      request.body,
    );
    response.status(201).json({ employee });
  }),
);

employeesRouter.patch(
  "/:id",
  validateBody(employeeUpdateSchema),
  asyncHandler(async (request, response) => {
    const employee = await employeesService.update(
      request.appContext!,
      readParam(request.params.id),
      request.body,
    );
    response.json({ employee });
  }),
);

employeesRouter.delete(
  "/:id",
  asyncHandler(async (request, response) => {
    const employee = await employeesService.softDelete(
      request.appContext!,
      readParam(request.params.id),
    );
    response.json({ employee });
  }),
);

employeesRouter.post(
  "/:id/invite",
  asyncHandler(async (request, response) => {
    const result = await employeesService.invite(
      request.appContext!,
      readParam(request.params.id),
    );
    response.json(result);
  }),
);

employeesRouter.post(
  "/:id/access/temporary-password",
  asyncHandler(async (request, response) => {
    const result = await employeesService.generateTemporaryPassword(
      request.appContext!,
      readParam(request.params.id),
    );
    response.json(result);
  }),
);

employeesRouter.post(
  "/:id/disable",
  asyncHandler(async (request, response) => {
    const employee = await employeesService.disable(
      request.appContext!,
      readParam(request.params.id),
    );
    response.json({ employee });
  }),
);

employeesRouter.post(
  "/:id/enable",
  asyncHandler(async (request, response) => {
    const employee = await employeesService.enable(
      request.appContext!,
      readParam(request.params.id),
    );
    response.json({ employee });
  }),
);

function readParam(value: string | string[] | undefined) {
  return Array.isArray(value) ? value[0] : (value ?? "");
}
