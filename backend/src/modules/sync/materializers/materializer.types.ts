import type { Prisma } from '@prisma/client';

import type { AppContext } from '../../app/app-context.types';
import type { SyncPushEventInput } from '../sync.schemas';

export type SyncMaterializerInput = {
  tx: Prisma.TransactionClient;
  context: AppContext;
  event: SyncPushEventInput;
  payload: Record<string, unknown>;
};

export type SyncMaterializerAccepted = {
  outcome: 'accepted';
  entityServerId?: string | null;
  materializedAt?: Date | null;
};

export type SyncMaterializerDuplicate = {
  outcome: 'duplicate';
  entityServerId?: string | null;
  serverVersion?: bigint | null;
};

export type SyncMaterializerRejected = {
  outcome: 'rejected';
  code: string;
  message: string;
  details?: Prisma.InputJsonValue;
};

export type SyncMaterializerConflict = {
  outcome: 'conflict';
  code: string;
  message: string;
  payload?: Prisma.InputJsonValue;
};

export type SyncMaterializerResult =
  | SyncMaterializerAccepted
  | SyncMaterializerDuplicate
  | SyncMaterializerRejected
  | SyncMaterializerConflict;
