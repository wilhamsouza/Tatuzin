import { prisma } from '../../database/prisma';
import { canViewSensitiveProductData } from '../products/product-access';
import { ProductsService } from '../products/products.service';
import type { AppContext } from './app-context.types';

const SERVER_FIRST_SNAPSHOT_FEATURES = [
  'products',
  'categories',
  'suppliers',
  'customers',
  'cash_sessions',
  'cash_movements',
  'fiado',
  'costs',
  'settings',
  'plan',
] as const;

export class AppSnapshotService {
  private readonly productsService = new ProductsService();

  async buildSnapshot(input: { context: AppContext; features: string[] }) {
    const requestedFeatures =
      input.features.length === 0
        ? [...SERVER_FIRST_SNAPSHOT_FEATURES]
        : SERVER_FIRST_SNAPSHOT_FEATURES.filter((feature) =>
            input.features.includes(feature),
          );

    const snapshots = await Promise.all(
      requestedFeatures.map((feature) =>
        this.buildFeatureSnapshot(input.context, feature),
      ),
    );
    const snapshotMap = Object.fromEntries(
      snapshots.map((snapshot) => [snapshot.feature, snapshot]),
    );
    const version = Math.max(
      0,
      ...snapshots.map((snapshot) =>
        snapshot.updatedAt == null
          ? 0
          : new Date(snapshot.updatedAt).getTime(),
      ),
    );

    return {
      ok: true,
      companyId: input.context.company.id,
      serverFirstSnapshotVersion: version.toString(),
      features: snapshotMap,
    };
  }

  private async buildFeatureSnapshot(
    context: AppContext,
    feature: (typeof SERVER_FIRST_SNAPSHOT_FEATURES)[number],
  ) {
    switch (feature) {
      case 'products':
        const includeSensitiveProductData =
          canViewSensitiveProductData(context);
        return this.buildModelSnapshot(feature, () =>
          prisma.product.findMany({
            where: { companyId: context.company.id },
            include: {
              variants: {
                orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
              },
              modifierGroups: {
                orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
                include: {
                  options: {
                    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
                  },
                },
              },
            },
            orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
          }),
          (product) =>
            this.productsService.toProductDto(product, {
              includeSensitiveData: includeSensitiveProductData,
            }),
        );
      case 'categories':
        return this.buildModelSnapshot(feature, () =>
          prisma.category.findMany({
            where: { companyId: context.company.id },
            orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
          }),
          (category) => ({
            id: category.id,
            companyId: category.companyId,
            localUuid: category.localUuid,
            name: category.name,
            description: category.description,
            isActive: category.isActive,
            deletedAt: category.deletedAt?.toISOString() ?? null,
            createdAt: category.createdAt.toISOString(),
            updatedAt: category.updatedAt.toISOString(),
          }),
        );
      case 'suppliers':
        return this.buildModelSnapshot(feature, () =>
          prisma.supplier.findMany({
            where: { companyId: context.company.id },
            orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
          }),
          (supplier) => ({
            id: supplier.id,
            companyId: supplier.companyId,
            localUuid: supplier.localUuid,
            name: supplier.name,
            tradeName: supplier.tradeName,
            phone: supplier.phone,
            email: supplier.email,
            address: supplier.address,
            document: supplier.document,
            contactPerson: supplier.contactPerson,
            notes: supplier.notes,
            isActive: supplier.isActive,
            deletedAt: supplier.deletedAt?.toISOString() ?? null,
            createdAt: supplier.createdAt.toISOString(),
            updatedAt: supplier.updatedAt.toISOString(),
          }),
        );
      case 'customers':
        return this.buildModelSnapshot(feature, () =>
          prisma.customer.findMany({
            where: { companyId: context.company.id },
            orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
          }),
          (customer) => ({
            id: customer.id,
            companyId: customer.companyId,
            localUuid: customer.localUuid,
            name: customer.name,
            phone: customer.phone,
            address: customer.address,
            notes: customer.notes,
            isActive: customer.isActive,
            deletedAt: customer.deletedAt?.toISOString() ?? null,
            createdAt: customer.createdAt.toISOString(),
            updatedAt: customer.updatedAt.toISOString(),
          }),
        );
      case 'cash_sessions':
        return this.buildModelSnapshot(feature, () =>
          prisma.cashSession.findMany({
            where: { companyId: context.company.id },
            include: {
              user: {
                select: { name: true },
              },
            },
            orderBy: [{ updatedAt: 'desc' }, { openedAt: 'desc' }],
          }),
          (session) => ({
            id: session.id,
            companyId: session.companyId,
            localUuid: session.localUuid,
            userId: session.userId,
            operatorName:
              cashSessionOperatorName(session.payload) ?? session.user?.name ?? null,
            status: session.status,
            openedAt: session.openedAt?.toISOString() ?? null,
            closedAt: session.closedAt?.toISOString() ?? null,
            openingBalanceCents: session.openingBalanceCents,
            closingBalanceCents: session.closingBalanceCents,
            expectedBalanceCents: session.expectedBalanceCents,
            notes: session.notes,
            createdAt: session.createdAt.toISOString(),
            updatedAt: session.updatedAt.toISOString(),
          }),
        );
      case 'cash_movements':
        return this.buildModelSnapshot(feature, () =>
          prisma.cashEvent.findMany({
            where: {
              companyId: context.company.id,
              cashSessionId: { not: null },
            },
            orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
          }),
          (movement) => ({
            id: movement.id,
            companyId: movement.companyId,
            cashSessionId: movement.cashSessionId,
            localUuid: movement.localUuid,
            eventType: movement.eventType,
            amountCents: movement.amountCents,
            paymentMethod: movement.paymentMethod,
            referenceType: movement.referenceType,
            referenceId: movement.referenceId,
            notes: movement.notes,
            createdAt: movement.createdAt.toISOString(),
            updatedAt: movement.updatedAt.toISOString(),
          }),
        );
      case 'fiado':
        return this.aggregateModel(feature, () =>
          prisma.fiadoPayment.aggregate({
            where: { companyId: context.company.id },
            _max: { updatedAt: true },
            _count: { _all: true },
          }),
        );
      case 'costs':
        return this.aggregateModel(feature, () =>
          prisma.cost.aggregate({
            where: { companyId: context.company.id },
            _max: { updatedAt: true },
            _count: { _all: true },
          }),
        );
      case 'settings':
        const company = await prisma.company.findUnique({
          where: { id: context.company.id },
          select: { updatedAt: true },
        });
        return {
          feature,
          mode: 'server_first_cache',
          updatedAt: company?.updatedAt.toISOString() ?? null,
          count: 1,
        };
      case 'plan':
        const license = await prisma.license.findUnique({
          where: { companyId: context.company.id },
          select: { updatedAt: true },
        });
        return {
          feature,
          mode: 'server_first_cache',
          updatedAt: license?.updatedAt.toISOString() ?? null,
          count: 1,
          plan: context.license.plan,
          licenseStatus: context.license.status,
          syncEnabled: context.license.syncEnabled,
        };
    }
  }

  private async aggregateModel(
    feature: string,
    aggregate: () => Promise<{
      _max: { updatedAt: Date | null };
      _count: { _all: number };
    }>,
  ) {
    const result = await aggregate();
    return {
      feature,
      mode: 'server_first_cache',
      updatedAt: result._max.updatedAt?.toISOString() ?? null,
      count: result._count._all,
    };
  }

  private async buildModelSnapshot<T extends { updatedAt: Date }>(
    feature: string,
    load: () => Promise<T[]>,
    mapItem: (item: T) => Record<string, unknown>,
  ) {
    const items = await load();
    const updatedAt = items.reduce<Date | null>(
      (latest, item) =>
        latest == null || item.updatedAt.getTime() > latest.getTime()
          ? item.updatedAt
          : latest,
      null,
    );

    return {
      feature,
      mode: 'server_first_cache',
      updatedAt: updatedAt?.toISOString() ?? null,
      count: items.length,
      items: items.map(mapItem),
    };
  }
}

function cashSessionOperatorName(payload: unknown) {
  if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
    return null;
  }

  const value = (payload as Record<string, unknown>).operatorName;
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : null;
}
