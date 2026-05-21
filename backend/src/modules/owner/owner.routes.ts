import type { NextFunction, Request, Response } from "express";
import { Router } from "express";

import { requireAppContext } from "../../shared/http/auth-middleware";
import { asyncHandler } from "../../shared/http/async-handler";
import { AppError } from "../../shared/http/app-error";
import { requireFeature } from "../../shared/http/feature-middleware";
import { validateBody, validateQuery } from "../../shared/http/validate";
import {
  billingCancelSchema,
  billingChangePlanSchema,
  billingSubscribeSchema,
} from "../billing/billing.schemas";
import { BillingService } from "../billing/billing.service";
import { CompanySettingsService } from "../app/company-settings.service";
import { companyReceiptSettingsPatchSchema } from "../app/company-settings.schemas";
import { EmployeeCommissionService } from "../employees/employee-commission.service";
import { requireAnyEmployeePermission } from "../employees/employee-permission-middleware";
import {
  employeeCommissionSettingsSchema,
  employeeCreateSchema,
  employeeUpdateSchema,
  type EmployeeCommissionSettingsInput,
} from "../employees/employees.schemas";
import { EmployeesService } from "../employees/employees.service";
import {
  ownerCommissionsQuerySchema,
  ownerCrmCustomersQuerySchema,
  ownerCrmSummaryQuerySchema,
  ownerEmployeeActivityQuerySchema,
  ownerEmployeesReportQuerySchema,
  ownerIdParamSchema,
  ownerInvoicesQuerySchema,
  ownerProductsReportQuerySchema,
  ownerReceivablesQuerySchema,
  ownerSalesSummaryQuerySchema,
  ownerStockSummaryQuerySchema,
  type OwnerCommissionsQueryInput,
  type OwnerCrmCustomersQueryInput,
  type OwnerCrmSummaryQueryInput,
  type OwnerEmployeeActivityQueryInput,
  type OwnerEmployeesReportQueryInput,
  type OwnerInvoicesQueryInput,
  type OwnerProductsReportQueryInput,
  type OwnerReceivablesQueryInput,
  type OwnerSalesSummaryQueryInput,
  type OwnerStockSummaryQueryInput,
} from "./owner.schemas";
import { OwnerService } from "./owner.service";

const ownerService = new OwnerService();
const employeesService = new EmployeesService();
const employeeCommissionService = new EmployeeCommissionService();
const companySettingsService = new CompanySettingsService();
const billingService = new BillingService();

export const ownerRouter = Router();

ownerRouter.use(
  requireAppContext,
  requireOwnerPanelAccess,
  requireFeature("ownerWebPanel"),
);

ownerRouter.get(
  "/company",
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getCompanySummary(request.appContext!));
  }),
);

ownerRouter.get(
  "/billing/status",
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getBillingStatus(request.appContext!));
  }),
);

ownerRouter.get(
  "/billing/invoices",
  requireOwnerRole,
  validateQuery(ownerInvoicesQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.listBillingInvoices(
        request.appContext!,
        request.query as unknown as OwnerInvoicesQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/employees",
  requireAnyEmployeePermission(["employees.manage", "reports.advanced"]),
  asyncHandler(async (request, response) => {
    response.json(await ownerService.listEmployees(request.appContext!));
  }),
);

ownerRouter.post(
  "/employees",
  requireAnyEmployeePermission(["employees.manage"]),
  validateBody(employeeCreateSchema),
  asyncHandler(async (request, response) => {
    const employee = await employeesService.create(
      request.appContext!,
      request.body,
    );
    response.status(201).json({ employee });
  }),
);

ownerRouter.patch(
  "/employees/:id",
  requireAnyEmployeePermission(["employees.manage"]),
  validateBody(employeeUpdateSchema),
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    const employee = await employeesService.update(
      request.appContext!,
      id,
      request.body,
    );
    response.json({ employee });
  }),
);

ownerRouter.post(
  "/employees/:id/access/temporary-password",
  requireAnyEmployeePermission(["employees.manage"]),
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    response.json(
      await employeesService.generateTemporaryPassword(request.appContext!, id),
    );
  }),
);

ownerRouter.post(
  "/employees/:id/disable",
  requireAnyEmployeePermission(["employees.manage"]),
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    const employee = await employeesService.disable(request.appContext!, id);
    response.json({ employee });
  }),
);

ownerRouter.post(
  "/employees/:id/enable",
  requireAnyEmployeePermission(["employees.manage"]),
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    const employee = await employeesService.enable(request.appContext!, id);
    response.json({ employee });
  }),
);

ownerRouter.get(
  "/commissions",
  requireAnyEmployeePermission(["employees.manage", "reports.advanced"]),
  validateQuery(ownerCommissionsQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.getCommissions(
        request.appContext!,
        request.query as unknown as OwnerCommissionsQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/employees/:id/commission-settings",
  requireAnyEmployeePermission(["employees.manage", "reports.advanced"]),
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    response.json(
      await employeeCommissionService.getSettings(request.appContext!, id),
    );
  }),
);

ownerRouter.patch(
  "/employees/:id/commission-settings",
  requireAnyEmployeePermission(["employees.manage"]),
  validateBody(employeeCommissionSettingsSchema),
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    response.json(
      await employeeCommissionService.updateSettings(
        request.appContext!,
        id,
        request.body as EmployeeCommissionSettingsInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/employees/:id/commissions",
  requireAnyEmployeePermission(["employees.manage", "reports.advanced"]),
  validateQuery(ownerCommissionsQuerySchema),
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    response.json(
      await employeeCommissionService.detail(
        request.appContext!,
        id,
        ownerPeriodToEmployeePeriod(
          request.query as unknown as OwnerCommissionsQueryInput,
        ),
      ),
    );
  }),
);

ownerRouter.get(
  "/employee-activity",
  requireAnyEmployeePermission(["reports.advanced"]),
  validateQuery(ownerEmployeeActivityQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.getEmployeeActivity(
        request.appContext!,
        request.query as unknown as OwnerEmployeeActivityQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/receipt-settings",
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getReceiptSettings(request.appContext!));
  }),
);

ownerRouter.patch(
  "/receipt-settings",
  validateBody(companyReceiptSettingsPatchSchema),
  asyncHandler(async (request, response) => {
    const result = await companySettingsService.updateReceiptSettings(
      request.appContext!,
      request.body,
    );
    response.json(ownerService.serializeAppReceiptSettings(result.company));
  }),
);

ownerRouter.get(
  "/devices",
  asyncHandler(async (request, response) => {
    response.json(await ownerService.listDevices(request.appContext!));
  }),
);

ownerRouter.get(
  "/sync/status",
  requireAnyEmployeePermission(["reports.advanced", "devices.manage"]),
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getSyncStatus(request.appContext!));
  }),
);

ownerRouter.get(
  "/dashboard",
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getDashboard(request.appContext!));
  }),
);

ownerRouter.get(
  "/dashboard/business",
  requireAnyEmployeePermission(["reports.advanced"]),
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getBusinessDashboard(request.appContext!));
  }),
);

ownerRouter.get(
  "/reports/sales-summary",
  requireAnyEmployeePermission(["reports.advanced"]),
  validateQuery(ownerSalesSummaryQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.getSalesSummary(
        request.appContext!,
        request.query as unknown as OwnerSalesSummaryQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/reports/products",
  requireAnyEmployeePermission(["reports.advanced"]),
  validateQuery(ownerProductsReportQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.getProductsReport(
        request.appContext!,
        request.query as unknown as OwnerProductsReportQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/stock/summary",
  requireAnyEmployeePermission(["reports.advanced"]),
  validateQuery(ownerStockSummaryQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.getStockSummary(
        request.appContext!,
        request.query as unknown as OwnerStockSummaryQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/crm/summary",
  requireAnyEmployeePermission(["reports.advanced"]),
  validateQuery(ownerCrmSummaryQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.getCrmSummary(
        request.appContext!,
        request.query as unknown as OwnerCrmSummaryQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/crm/customers",
  requireAnyEmployeePermission(["reports.advanced"]),
  validateQuery(ownerCrmCustomersQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.listCrmCustomers(
        request.appContext!,
        request.query as unknown as OwnerCrmCustomersQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/crm/customers/:id",
  requireAnyEmployeePermission(["reports.advanced"]),
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    response.json(
      await ownerService.getCrmCustomerDetail(request.appContext!, id),
    );
  }),
);

ownerRouter.get(
  "/financial/receivables",
  requireAnyEmployeePermission(["reports.advanced"]),
  validateQuery(ownerReceivablesQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.listReceivables(
        request.appContext!,
        request.query as unknown as OwnerReceivablesQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/reports/employees",
  requireAnyEmployeePermission(["reports.advanced"]),
  validateQuery(ownerEmployeesReportQuerySchema),
  asyncHandler(async (request, response) => {
    response.json(
      await ownerService.getEmployeeReports(
        request.appContext!,
        request.query as unknown as OwnerEmployeesReportQueryInput,
      ),
    );
  }),
);

ownerRouter.get(
  "/reports/catalog",
  requireAnyEmployeePermission(["reports.advanced"]),
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getReportsCatalog(request.appContext!));
  }),
);

ownerRouter.get(
  "/billing/plans",
  requireOwnerRole,
  asyncHandler(async (_request, response) => {
    response.json({ items: billingService.listPlans() });
  }),
);

ownerRouter.post(
  "/billing/subscribe",
  requireOwnerRole,
  validateBody(billingSubscribeSchema),
  asyncHandler(async (request, response) => {
    const result = await billingService.subscribe(
      request.appContext!,
      request.body,
    );
    response.status(result.checkoutUrl == null ? 200 : 201).json(result);
  }),
);

ownerRouter.post(
  "/billing/refresh",
  requireOwnerRole,
  asyncHandler(async (request, response) => {
    response.json(await billingService.refresh(request.appContext!));
  }),
);

ownerRouter.post(
  "/billing/cancel",
  requireOwnerRole,
  validateBody(billingCancelSchema),
  asyncHandler(async (request, response) => {
    response.json(
      await billingService.cancelSubscription(
        request.appContext!,
        request.body,
      ),
    );
  }),
);

ownerRouter.post(
  "/billing/resume",
  requireOwnerRole,
  asyncHandler(async (request, response) => {
    response.json(await billingService.resumeSubscription(request.appContext!));
  }),
);

ownerRouter.post(
  "/billing/change-plan",
  requireOwnerRole,
  validateBody(billingChangePlanSchema),
  asyncHandler(async (request, response) => {
    response.json(
      await billingService.changePlan(request.appContext!, request.body),
    );
  }),
);

function requireOwnerPanelAccess(
  request: Request,
  _response: Response,
  next: NextFunction,
) {
  const role = request.appContext?.membership.role;
  if (role === "OWNER" || role === "ADMIN") {
    next();
    return;
  }

  next(
    new AppError(
      "Voce nao tem permissao para acessar este painel.",
      403,
      "OWNER_PANEL_ACCESS_REQUIRED",
    ),
  );
}

function requireOwnerRole(
  request: Request,
  _response: Response,
  next: NextFunction,
) {
  if (request.appContext?.membership.role === "OWNER") {
    next();
    return;
  }

  next(
    new AppError(
      "Apenas o dono da empresa pode gerenciar assinatura.",
      403,
      "OWNER_REQUIRED",
    ),
  );
}

function ownerPeriodToEmployeePeriod(query: {
  startDate?: string;
  endDate?: string;
}) {
  const today = new Date();
  const to = dateOnly(query.endDate == null ? today : new Date(query.endDate));
  const defaultFrom = new Date(`${to}T00:00:00.000Z`);
  defaultFrom.setUTCDate(defaultFrom.getUTCDate() - 29);
  const from = dateOnly(
    query.startDate == null ? defaultFrom : new Date(query.startDate),
  );
  return { from, to };
}

function dateOnly(value: Date) {
  return value.toISOString().slice(0, 10);
}
