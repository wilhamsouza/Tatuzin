import cors from 'cors';
import express from 'express';

import { env } from './config/env';
import { analyticsDashboardRouter } from './modules/analytics/dashboard/analytics-dashboard.routes';
import { analyticsReportsRouter } from './modules/analytics/reports/analytics-reports.routes';
import { tenantAnalyticsReportsRouter } from './modules/analytics/reports/tenant-analytics-reports.routes';
import { analyticsSnapshotsRouter } from './modules/analytics/snapshots/analytics-snapshots.routes';
import { adminRouter } from './modules/admin/admin.routes';
import { companyRouter, authRouter } from './modules/auth/auth.routes';
import { crmRouter } from './modules/crm/crm.routes';
import { costsRouter } from './modules/costs/costs.routes';
import { hybridGovernanceRouter } from './modules/hybrid-governance/hybrid-governance.routes';
import { cashEventsRouter } from './modules/cash/cash-events.routes';
import { categoriesRouter } from './modules/categories/categories.routes';
import { customersRouter } from './modules/customers/customers.routes';
import { fiadoPaymentsRouter } from './modules/fiado/fiado-payments.routes';
import { financialEventsRouter } from './modules/financial-events/financial-events.routes';
import { inventoryRouter } from './modules/inventory/inventory.routes';
import { productRecipesRouter } from './modules/product-recipes/product-recipes.routes';
import { productsRouter } from './modules/products/products.routes';
import { purchasesRouter } from './modules/purchases/purchases.routes';
import { salesRouter } from './modules/sales/sales.routes';
import { suppliesRouter } from './modules/supplies/supplies.routes';
import { suppliersRouter } from './modules/suppliers/suppliers.routes';
import { AppError } from './shared/http/app-error';
import { errorHandler } from './shared/http/error-handler';
import { requestContextMiddleware } from './shared/http/request-context';
import {
  buildLivenessSnapshot,
  buildReadinessSnapshot,
} from './shared/platform/platform-health';

function isAllowedOrigin(origin: string | undefined): boolean {
  if (origin == null || origin.length == 0) {
    return true;
  }

  return env.corsOrigins.includes(origin);
}

export function createApp() {
  const app = express();

  app.disable('x-powered-by');
  app.set('trust proxy', env.trustProxy);
  app.use(requestContextMiddleware);
  app.use((request, response, next) => {
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('X-Frame-Options', 'DENY');
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
    response.setHeader('Cross-Origin-Resource-Policy', 'same-site');
    next();
  });
  app.use(
    cors({
      origin(origin, callback) {
        if (isAllowedOrigin(origin)) {
          callback(null, true);
          return;
        }

        callback(
          new AppError(
            'Origem nao permitida para este backend.',
            403,
            'CORS_ORIGIN_DENIED',
          ),
        );
      },
      methods: ['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'X-Request-Id'],
      exposedHeaders: [
        'X-Request-Id',
        'X-RateLimit-Limit',
        'X-RateLimit-Remaining',
        'X-RateLimit-Reset',
        'Retry-After',
      ],
    }),
  );
  app.use(express.json({ limit: '1mb' }));

  app.get('/api/health', (request, response) => {
    response.json({
      ...buildLivenessSnapshot(),
      requestId: request.requestId,
    });
  });

  app.get('/api/readiness', async (request, response) => {
    const snapshot = await buildReadinessSnapshot();
    response.status(snapshot.ready ? 200 : 503).json({
      ...snapshot,
      requestId: request.requestId,
    });
  });

  app.get('/api/fiado/health', (_request, response) => {
    response.json({ ok: true, feature: 'fiado' });
  });

  app.get('/api/cash/health', (_request, response) => {
    response.json({ ok: true, feature: 'cash' });
  });

  app.use('/api/auth', authRouter);
  app.use('/api/admin', adminRouter);
  app.use('/api/admin/analytics/dashboard', analyticsDashboardRouter);
  app.use('/api/admin/analytics/reports', analyticsReportsRouter);
  app.use('/api/admin/analytics/snapshots', analyticsSnapshotsRouter);
  app.use('/api/analytics/reports', tenantAnalyticsReportsRouter);
  app.use('/api/admin/crm', crmRouter);
  app.use('/api/admin/hybrid-governance', hybridGovernanceRouter);
  app.use('/api/companies', companyRouter);
  app.use('/api/categories', categoriesRouter);
  app.use('/api/products', productsRouter);
  app.use('/api/product-recipes', productRecipesRouter);
  app.use('/api/customers', customersRouter);
  app.use('/api/supplies', suppliesRouter);
  app.use('/api/suppliers', suppliersRouter);
  app.use('/api/purchases', purchasesRouter);
  app.use('/api/sales', salesRouter);
  app.use('/api/inventory', inventoryRouter);
  app.use('/api/costs', costsRouter);
  app.use('/api/financial-events', financialEventsRouter);
  app.use('/api/fiado', fiadoPaymentsRouter);
  app.use('/api/cash', cashEventsRouter);

  app.use(errorHandler);

  return app;
}
