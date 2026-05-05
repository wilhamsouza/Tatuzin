import type { Prisma } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { SyncVersionService } from './sync-version.service';

const versionService = new SyncVersionService();

export class SyncCheckpointService {
  async recordPush(input: {
    tx: Prisma.TransactionClient;
    companyId: string;
    deviceId: string;
    feature: string;
    serverVersion: bigint;
  }) {
    await input.tx.syncCheckpoint.upsert({
      where: {
        companyId_deviceId_feature: {
          companyId: input.companyId,
          deviceId: input.deviceId,
          feature: input.feature,
        },
      },
      create: {
        companyId: input.companyId,
        deviceId: input.deviceId,
        feature: input.feature,
        lastServerVersion: input.serverVersion,
        lastPushedAt: new Date(),
      },
      update: {
        lastServerVersion: input.serverVersion,
        lastPushedAt: new Date(),
      },
    });
  }

  async recordPull(input: {
    companyId: string;
    deviceId: string;
    features: string[];
    serverVersion: bigint;
  }) {
    const features = [...new Set(input.features)];
    for (const feature of features) {
      await prisma.syncCheckpoint.upsert({
        where: {
          companyId_deviceId_feature: {
            companyId: input.companyId,
            deviceId: input.deviceId,
            feature,
          },
        },
        create: {
          companyId: input.companyId,
          deviceId: input.deviceId,
          feature,
          lastServerVersion: input.serverVersion,
          lastPulledAt: new Date(),
        },
        update: {
          lastServerVersion: input.serverVersion,
          lastPulledAt: new Date(),
        },
      });
    }
  }

  async listForDevice(input: { companyId: string; deviceId: string }) {
    const checkpoints = await prisma.syncCheckpoint.findMany({
      where: {
        companyId: input.companyId,
        deviceId: input.deviceId,
      },
      orderBy: {
        feature: 'asc',
      },
    });

    return checkpoints.map((checkpoint) => ({
      id: checkpoint.id,
      feature: checkpoint.feature,
      lastServerVersion: versionService.toDto(
        checkpoint.lastServerVersion,
      ),
      lastPushedAt: checkpoint.lastPushedAt?.toISOString() ?? null,
      lastPulledAt: checkpoint.lastPulledAt?.toISOString() ?? null,
      updatedAt: checkpoint.updatedAt.toISOString(),
    }));
  }
}
