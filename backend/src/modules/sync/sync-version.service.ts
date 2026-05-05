import type { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';

export class SyncVersionService {
  async getCurrentVersion(companyId: string) {
    const state = await prisma.companySyncState.findUnique({
      where: { companyId },
    });

    return state?.currentVersion ?? 0n;
  }

  async getOrCreateState(companyId: string) {
    return prisma.companySyncState.upsert({
      where: { companyId },
      create: {
        companyId,
        currentVersion: 0n,
        serverFirstSnapshotVersion: 0n,
        updatedAt: new Date(),
      },
      update: {},
    });
  }

  async nextCompanyVersion(tx: Prisma.TransactionClient, companyId: string) {
    const state = await tx.companySyncState.upsert({
      where: { companyId },
      create: {
        companyId,
        currentVersion: 1n,
        serverFirstSnapshotVersion: 0n,
        updatedAt: new Date(),
      },
      update: {
        currentVersion: {
          increment: 1n,
        },
      },
    });

    return state.currentVersion;
  }

  toDto(version: bigint | number | null | undefined) {
    return (version ?? 0).toString();
  }
}
