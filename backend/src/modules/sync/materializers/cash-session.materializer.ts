import {
  asRecord,
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
  persistableLocalSequence,
} from './payload-utils';
import type {
  SyncMaterializerInput,
  SyncMaterializerResult,
} from './materializer.types';

export class CashSessionMaterializer {
  async materialize(
    input: SyncMaterializerInput,
  ): Promise<SyncMaterializerResult> {
    if (!['create', 'update', 'upsert'].includes(input.event.operation)) {
      return {
        outcome: 'rejected',
        code: 'INVALID_OPERATION',
        message: 'cashSession aceita create, update ou upsert.',
      };
    }

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
    const storedLocalSequence = persistableLocalSequence(localSequence);

    if (
      existing != null &&
      ['update', 'upsert'].includes(input.event.operation) &&
      storedLocalSequence != null &&
      existing.lastLocalSequence != null &&
      existing.lastLocalSequence > storedLocalSequence
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

    const requestedStatusRaw = firstString(input.payload, ['status', 'state']);
    const requestedStatus =
      requestedStatusRaw == null
        ? null
        : normalizeCashSessionStatus(requestedStatusRaw);
    if (requestedStatus !== 'open' && requestedStatus !== 'closed') {
      return {
        outcome: 'rejected',
        code:
          requestedStatusRaw == null
            ? 'CASH_SESSION_INVALID_PAYLOAD'
            : 'CASH_SESSION_INVALID_STATUS',
        message:
          requestedStatusRaw == null
            ? 'Payload de sessao de caixa nao possui os dados minimos para materializacao segura.'
            : 'Status de sessao de caixa invalido para sync operacional.',
        details: {
          entity: input.event.entity,
          operation: input.event.operation,
          entityLocalId: input.event.entityLocalId,
          status: requestedStatusRaw,
          ...(requestedStatusRaw == null
            ? { missingFields: ['status'] }
            : {}),
        },
      };
    }
    const normalizedStatus = requestedStatus as 'open' | 'closed';

    if (input.event.operation === 'create' && existing != null) {
      await this.backfillDuplicateCreate(input, existing);
      return { outcome: 'duplicate', entityServerId: existing.id };
    }

    if (
      existing != null &&
      existing.status === 'closed' &&
      isOpenStatus(normalizedStatus)
    ) {
      return {
        outcome: 'conflict',
        code: 'CASH_SESSION_CLOSED',
        message: 'Sessao de caixa fechada nao pode ser reaberta.',
        payload: {
          cashSessionId: existing.id,
          localUuid,
          currentStatus: existing.status,
          requestedStatus: normalizedStatus,
        },
      };
    }

    const openedAtField = this.readDateField(input, ['openedAt', 'createdAt']);
    const closedAtField = this.readDateField(input, [
      'closedAt',
      'finishedAt',
      'updatedAt',
    ]);

    const invalidPayload = this.invalidPayloadResult({
      input,
      existing,
      localUuid,
      requestedStatus: normalizedStatus,
      openedAtField,
      closedAtField,
    });
    if (invalidPayload != null) {
      return invalidPayload;
    }

    const defaultOpenedAt = existing?.openedAt ?? new Date(input.event.occurredAt);
    const defaultClosedAt = existing?.closedAt ?? new Date(input.event.occurredAt);
    const openedAt =
      openedAtField.value ??
      firstDate(input.payload, ['openedAt', 'createdAt'], defaultOpenedAt);
    const closedAt = isClosedStatus(normalizedStatus)
      ? closedAtField.value ??
        firstDate(
          input.payload,
          ['closedAt', 'finishedAt', 'updatedAt'],
          defaultClosedAt,
        )
      : null;
    const mergedPayload = this.mergePayload(existing?.payload, input.payload);

    const data = {
      deviceId: input.context.device.id,
      userId: input.context.user.id,
      localId: firstIdentity(input.payload, ['localId', 'id']),
      status: normalizedStatus,
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
      notes:
        firstString(input.payload, ['notes', 'description']) ??
        existing?.notes,
      payload: jsonPayload(mergedPayload),
      lastLocalSequence:
        storedLocalSequence ?? existing?.lastLocalSequence ?? null,
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

  private invalidPayloadResult(input: {
    input: SyncMaterializerInput;
    existing: {
      openedAt: Date | null;
      closedAt: Date | null;
      payload: unknown;
    } | null;
    localUuid: string;
    requestedStatus: string;
    openedAtField: DateField;
    closedAtField: DateField;
  }) {
    const missingFields: string[] = [];
    const invalidFields: string[] = [];

    if (input.openedAtField.invalid) {
      invalidFields.push('openedAt');
    }

    if (input.closedAtField.invalid) {
      invalidFields.push('closedAt');
    }

    if (input.existing == null && input.openedAtField.value == null) {
      missingFields.push('openedAt');
    }

    if (missingFields.length === 0 && invalidFields.length === 0) {
      return null;
    }

    return {
      outcome: 'rejected' as const,
      code: 'CASH_SESSION_INVALID_PAYLOAD',
      message:
        'Payload de sessao de caixa nao possui os dados minimos para materializacao segura.',
      details: {
        entity: input.input.event.entity,
        operation: input.input.event.operation,
        entityLocalId: input.input.event.entityLocalId,
        localUuid: input.localUuid,
        status: input.requestedStatus,
        missingFields,
        invalidFields,
      },
    };
  }

  private readDateField(
    input: SyncMaterializerInput,
    keys: string[],
  ): DateField {
    const raw = firstString(input.payload, keys);
    if (raw == null) {
      return { value: null, invalid: false };
    }

    const value = new Date(raw);
    if (Number.isNaN(value.getTime())) {
      return { value: null, invalid: true };
    }

    return { value, invalid: false };
  }

  private mergePayload(existingPayload: unknown, payload: Record<string, unknown>) {
    const merged = {
      ...asRecord(existingPayload),
      ...payload,
    };
    const operatorName =
      firstString(payload, ['operatorName']) ??
      firstString(asRecord(existingPayload), ['operatorName']);

    return operatorName == null
      ? merged
      : {
          ...merged,
          operatorName,
        };
  }

  private async backfillDuplicateCreate(
    input: SyncMaterializerInput,
    existing: ExistingCashSession,
  ) {
    const localId = firstIdentity(input.payload, ['localId', 'id']);
    const openedAtField = this.readDateField(input, ['openedAt', 'createdAt']);
    const mergedPayload = this.mergePayload(existing.payload, input.payload);
    const notes = firstString(input.payload, ['notes', 'description']);

    const patch: Record<string, unknown> = {};

    if (existing.localId == null && localId != null) {
      patch.localId = localId;
    }

    if (existing.openedAt == null && openedAtField.value != null) {
      patch.openedAt = openedAtField.value;
    }

    if (existing.deviceId == null && input.context.device.id != null) {
      patch.deviceId = input.context.device.id;
    }

    if (existing.userId == null && input.context.user.id != null) {
      patch.userId = input.context.user.id;
    }

    if (existing.notes == null && notes != null) {
      patch.notes = notes;
    }

    const hasMergedPayloadChanges =
      JSON.stringify(asRecord(existing.payload)) !== JSON.stringify(mergedPayload);
    if (hasMergedPayloadChanges) {
      patch.payload = jsonPayload(mergedPayload);
    }

    if (Object.keys(patch).length === 0) {
      return;
    }

    await input.tx.cashSession.update({
      where: { id: existing.id },
      data: patch,
    });
  }
}

type DateField = {
  value: Date | null;
  invalid: boolean;
};

type ExistingCashSession = {
  id: string;
  deviceId: string | null;
  userId: string | null;
  localId: string | null;
  openedAt: Date | null;
  notes: string | null;
  payload: unknown;
};
