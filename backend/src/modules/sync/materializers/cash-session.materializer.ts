import {
  firstDate,
  firstIdentity,
  firstInt,
  firstString,
  isClosedStatus,
  isOpenStatus,
  jsonPayload,
  localIdentityFor,
  localSequenceFor,
  normalizeCashSessionStatus,
} from './payload-utils';
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from './materializer.types';

export class CashSessionMaterializer {
  async materialize(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    const localUuid = localIdentityFor(input.event, input.payload);
    if (localUuid == null) {
      return {
        outcome: 'rejected',
        code: 'LOCAL_ID_REQUIRED',
        message: 'cashSession precisa de entityLocalId, uuid ou localId.',
      };
    }

    const existing = await input.tx.cashSession.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
    const localSequence = localSequenceFor(input.event, input.payload);

    if (input.event.operation === 'create' && existing != null) {
      return { outcome: 'duplicate', entityServerId: existing.id };
    }

    if (
      existing != null &&
      ['update', 'upsert'].includes(input.event.operation) &&
      localSequence != null &&
      existing.lastLocalSequence != null &&
      existing.lastLocalSequence > localSequence
    ) {
      return {
        outcome: 'conflict',
        code: 'STALE_LOCAL_SEQUENCE',
        message:
          'Evento operacional possui localSequence anterior ao ultimo evento materializado para a entidade.',
        payload: {
          entity: input.event.entity,
          entityLocalId: input.event.entityLocalId,
          localUuid,
          localSequence,
          latestLocalSequence: existing.lastLocalSequence,
        },
      };
    }

    const requestedStatus = normalizeCashSessionStatus(
      firstString(input.payload, ['status', 'state']),
    );

    if (
      existing != null &&
      existing.status === 'closed' &&
      isOpenStatus(requestedStatus)
    ) {
      return {
        outcome: 'conflict',
        code: 'CASH_SESSION_CLOSED',
        message: 'Sessao de caixa fechada nao pode ser reaberta.',
        payload: {
          cashSessionId: existing.id,
          localUuid,
          currentStatus: existing.status,
          requestedStatus,
        },
      };
    }

    const now = new Date();
    const openedAt = firstDate(input.payload, ['openedAt', 'createdAt'], now);
    const closedAt = isClosedStatus(requestedStatus)
      ? firstDate(input.payload, ['closedAt', 'finishedAt', 'updatedAt'], now)
      : null;

    const data = {
      deviceId: input.context.device.id,
      userId: input.context.user.id,
      localId: firstIdentity(input.payload, ['localId', 'id']),
      status: requestedStatus,
      openedAt,
      closedAt,
      openingBalanceCents:
        firstInt(input.payload, ['openingBalanceCents', 'initialFloatCents']) ??
        existing?.openingBalanceCents ??
        0,
      closingBalanceCents:
        firstInt(input.payload, ['closingBalanceCents', 'countedBalanceCents']) ??
        existing?.closingBalanceCents,
      expectedBalanceCents:
        firstInt(input.payload, ['expectedBalanceCents']) ??
        existing?.expectedBalanceCents,
      notes: firstString(input.payload, ['notes', 'description']),
      payload: jsonPayload(input.payload),
      lastLocalSequence:
        localSequence ?? existing?.lastLocalSequence ?? null,
    };

    if (existing == null) {
      const created = await input.tx.cashSession.create({
        data: {
          companyId: input.context.company.id,
          localUuid,
          ...data,
        },
      });
      return {
        outcome: 'accepted',
        entityServerId: created.id,
        materializedAt: created.updatedAt,
      };
    }

    const updated = await input.tx.cashSession.update({
      where: { id: existing.id },
      data,
    });

    return {
      outcome: 'accepted',
      entityServerId: updated.id,
      materializedAt: updated.updatedAt,
    };
  }
}
