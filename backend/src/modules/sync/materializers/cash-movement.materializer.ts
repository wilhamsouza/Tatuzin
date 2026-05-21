import {
  firstDate,
  domainIdentityFor,
  firstIdentity,
  firstInt,
  firstString,
  firstUuid,
  isClosedStatus,
} from './payload-utils';
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from './materializer.types';
import {
  canManageOtherCashSessions,
  requireSyncPermission,
} from './sync-authorization';

export class CashMovementMaterializer {
  async materialize(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (!['create', 'append', 'upsert'].includes(input.event.operation)) {
      return {
        outcome: 'rejected',
        code: 'INVALID_OPERATION',
        message: 'cashMovement aceita apenas create, append ou upsert.',
      };
    }

    const localUuid = domainIdentityFor(
      input.event,
      input.payload,
      [
        'localMovementUuid',
        'movementUuid',
        'uuid',
        'localUuid',
        'localId',
        'id',
      ],
      { preferIdempotencyKey: true },
    );
    if (localUuid == null) {
      return {
        outcome: 'rejected',
        code: 'LOCAL_ID_REQUIRED',
        message: 'cashMovement precisa de entityLocalId, uuid ou localId.',
      };
    }

    const existing = await input.tx.cashEvent.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
    if (existing != null) {
      return { outcome: 'duplicate', entityServerId: existing.id };
    }

    const amountCents = firstInt(input.payload, ['amountCents', 'amount']);
    if (amountCents == null || amountCents === 0) {
      return {
        outcome: 'rejected',
        code: 'INVALID_CASH_MOVEMENT_AMOUNT',
        message: 'cashMovement precisa de amountCents diferente de zero.',
      };
    }

    const cashSession = await this.findCashSession(input);
    const authorization = this.authorizeCashMovement(input, cashSession);
    if (authorization != null) {
      return authorization;
    }

    if (cashSession != null && isClosedStatus(cashSession.status)) {
      return {
        outcome: 'conflict',
        code: 'CASH_SESSION_CLOSED',
        message: 'Movimento de caixa nao pode ser criado em caixa fechado.',
        payload: {
          cashSessionId: cashSession.id,
          localUuid: cashSession.localUuid,
        },
      };
    }

    const created = await input.tx.cashEvent.create({
      data: {
        companyId: input.context.company.id,
        cashSessionId: cashSession?.id,
        localUuid,
        eventType:
          firstString(input.payload, ['eventType', 'type']) ?? 'cashMovement',
        amountCents,
        paymentMethod: firstString(input.payload, ['paymentMethod']),
        referenceType: cashSession == null ? null : 'cashSession',
        referenceId: cashSession?.id,
        notes: firstString(input.payload, ['description', 'notes']),
        createdAt: firstDate(input.payload, ['createdAt', 'occurredAt'], new Date()),
      },
    });

    return {
      outcome: 'accepted',
      entityServerId: created.id,
      materializedAt: created.updatedAt,
    };
  }

  private async findCashSession(input: SyncMaterializerInput) {
    const cashSessionId = firstUuid(input.payload, [
      'cashSessionId',
      'cashSessionServerId',
    ]);
    if (cashSessionId != null) {
      return input.tx.cashSession.findFirst({
        where: {
          id: cashSessionId,
          companyId: input.context.company.id,
        },
      });
    }

    const localUuid = firstIdentity(input.payload, [
      'cashSessionLocalId',
      'cashSessionUuid',
      'sessionUuid',
    ]);
    if (localUuid != null) {
      const byUuid = await input.tx.cashSession.findUnique({
        where: {
          companyId_localUuid: {
            companyId: input.context.company.id,
            localUuid,
          },
        },
      });
      if (byUuid != null) {
        return byUuid;
      }
    }

    const localId = firstIdentity(input.payload, ['sessionId', 'cashSessionLocalNumericId']);
    if (localId == null) {
      return null;
    }

    return input.tx.cashSession.findFirst({
      where: {
        companyId: input.context.company.id,
        localId,
      },
    });
  }

  private authorizeCashMovement(
    input: SyncMaterializerInput,
    cashSession: { userId: string | null } | null,
  ): SyncMaterializerResult | null {
    const permission = requireSyncPermission(
      input,
      'cash.withdraw',
      'Voce nao tem permissao para movimentar caixa.',
    );
    if (permission != null) {
      return permission;
    }

    if (
      cashSession != null &&
      cashSession.userId !== input.context.user.id &&
      !canManageOtherCashSessions(input)
    ) {
      return {
        outcome: 'rejected',
        code: 'CASH_MOVEMENT_OTHER_FORBIDDEN',
        message:
          'Voce nao tem permissao para movimentar caixa de outro funcionario.',
      };
    }

    return null;
  }
}
