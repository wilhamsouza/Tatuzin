import type { NextFunction, Request, Response } from 'express';
import { Router } from 'express';

import { requireAppContext } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { AppError } from '../../shared/http/app-error';
import { requireFeature } from '../../shared/http/feature-middleware';
import { validateQuery } from '../../shared/http/validate';
import {
  ownerCrmCustomersQuerySchema,
  ownerCrmSummaryQuerySchema,
  ownerEmployeesReportQuerySchema,
  ownerIdParamSchema,
  ownerInvoicesQuerySchema,
  ownerProductsReportQuerySchema,
  ownerReceivablesQuerySchema,
  ownerSalesSummaryQuerySchema,
  ownerStockSummaryQuerySchema,
  type OwnerCrmCustomersQueryInput,
  type OwnerCrmSummaryQueryInput,
  type OwnerEmployeesReportQueryInput,
  type OwnerInvoicesQueryInput,
  type OwnerProductsReportQueryInput,
  type OwnerReceivablesQueryInput,
  type OwnerSalesSummaryQueryInput,
  type OwnerStockSummaryQueryInput,
} from './owner.schemas';
import { OwnerService } from './owner.service';

const ownerService = new OwnerService();

export const ownerRouter = Router();

ownerRouter.use(
  requireAppContext,
  requireOwnerMembership,
  requireFeature('ownerWebPanel'),
);

ownerRouter.get(
  '/company',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getCompanySummary(request.appContext!));
  }),
);

ownerRouter.get(
  '/billing/status',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getBillingStatus(request.appContext!));
  }),
);

ownerRouter.get(
  '/billing/invoices',
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
  '/employees',
  asyncHandler(async (_request, response) => {
    response.json(ownerService.getEmployeesPlaceholder());
  }),
);

ownerRouter.get(
  '/devices',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.listDevices(request.appContext!));
  }),
);

ownerRouter.get(
  '/dashboard',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getDashboard(request.appContext!));
  }),
);

ownerRouter.get(
  '/dashboard/business',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getBusinessDashboard(request.appContext!));
  }),
);

ownerRouter.get(
  '/reports/sales-summary',
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
  '/reports/products',
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
  '/stock/summary',
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
  '/crm/summary',
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
  '/crm/customers',
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
  '/crm/customers/:id',
  asyncHandler(async (request, response) => {
    const { id } = ownerIdParamSchema.parse(request.params);
    response.json(
      await ownerService.getCrmCustomerDetail(request.appContext!, id),
    );
  }),
);

ownerRouter.get(
  '/financial/receivables',
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
  '/reports/employees',
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
  '/reports/catalog',
  asyncHandler(async (request, response) => {
    response.json(await ownerService.getReportsCatalog(request.appContext!));
  }),
);

function requireOwnerMembership(
  request: Request,
  _response: Response,
  next: NextFunction,
) {
  if (request.appContext?.membership.role === 'OWNER') {
    next();
    return;
  }

  next(
    new AppError(
      'Apenas o dono da empresa pode acessar o painel owner.',
      403,
      'OWNER_REQUIRED',
    ),
  );
}
