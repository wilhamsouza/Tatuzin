import { prisma } from '../../database/prisma';
import type { AppContext } from './app-context.types';

const SERVER_FIRST_SNAPSHOT_FEATURES = [
  'products',
  'categories',
  'suppliers',
  'customers',
  'fiado',
  'costs',
  'settings',
  'plan',
] as const;

export class AppSnapshotService {
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
        return this.aggregateModel(feature, () =>
          prisma.product.aggregate({
            where: { companyId: context.company.id },
            _max: { updatedAt: true },
            _count: { _all: true },
          }),
        );
      case 'categories':
        return this.aggregateModel(feature, () =>
          prisma.category.aggregate({
            where: { companyId: context.company.id },
            _max: { updatedAt: true },
            _count: { _all: true },
          }),
        );
      case 'suppliers':
        return this.aggregateModel(feature, () =>
          prisma.supplier.aggregate({
            where: { companyId: context.company.id },
            _max: { updatedAt: true },
            _count: { _all: true },
          }),
        );
      case 'customers':
        return this.aggregateModel(feature, () =>
          prisma.customer.aggregate({
            where: { companyId: context.company.id },
            _max: { updatedAt: true },
            _count: { _all: true },
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
}
