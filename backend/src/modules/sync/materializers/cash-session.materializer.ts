import { openingDetailsSchema, closingDetailsSchema, validateCashV2Count, cashMetadataEqual } from './cash-session-v2';
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
import {
  canManageOtherCashSessions,
  requireSyncPermission,
} from './sync-authorization';

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

    let existing = await input.tx.cashSession.findUnique({
      where: {
        companyId_localUuid: {
          companyId: input.context.company.id,
          localUuid,
        },
      },
    });
    if (existing != null && asRecord(asRecord(existing.payload).openingDetails).version === 2) {
      await input.tx.$queryRaw`SELECT "id" FROM "CashSession" WHERE "id" = ${existing.id} AND "companyId" = ${input.context.company.id} FOR UPDATE`;
      existing = await input.tx.cashSession.findUnique({where:{companyId_localUuid:{companyId:input.context.company.id,localUuid}}});
    }
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

    const savedPayload = asRecord(existing?.payload);
    const storedOpening = savedPayload.openingDetails;
    const openingRaw = input.payload.openingDetails ?? storedOpening;
    const closingRaw = input.payload.closingDetails ?? savedPayload.closingDetails;
    const v2 = openingRaw != null || closingRaw != null;
    const invalidV2 = (message: string): SyncMaterializerResult => ({ outcome: 'rejected', code: 'CASH_SESSION_INVALID_V2', message });
    const conflictV2 = (code: string, message: string): SyncMaterializerResult => ({ outcome: 'conflict', code, message });
    let opening: ReturnType<typeof openingDetailsSchema.parse> | undefined;
    let closing: ReturnType<typeof closingDetailsSchema.parse> | undefined;
    if (v2) {
      const v2Authorization = this.authorizeCashSessionChange({ input, existing, requestedStatus: normalizedStatus });
      if (v2Authorization != null) return v2Authorization;
      const parsedOpening = openingDetailsSchema.safeParse(openingRaw);
      if (!parsedOpening.success) return invalidV2('Contagem de abertura V2 invalida.');
      opening = parsedOpening.data;
      if (!validateCashV2Count(opening, opening.countedAmountCents)) return invalidV2('Total de cedulas/moedas de abertura invalido.');
      if (input.payload.openingBalanceCents !== undefined && input.payload.openingBalanceCents !== opening.countedAmountCents) return invalidV2('Saldo de abertura diverge da contagem.');
      if (existing != null && storedOpening == null) return conflictV2('CASH_SESSION_LEGACY_IMMUTABLE', 'Sessao legada nao pode receber politica retroativa.');
      const pendingFlag = input.payload.awaitingInitialFloatConfirmation;
      if (pendingFlag !== undefined && typeof pendingFlag !== 'boolean') return invalidV2('Confirmacao do fundo inicial deve ser booleana.');
      const wasPending = savedPayload.awaitingInitialFloatConfirmation === true;
      const pending = pendingFlag === undefined ? wasPending : pendingFlag;
      if (existing == null && pending && (normalizedStatus !== 'open' || opening.countedAmountCents !== 0)) return invalidV2('Abertura provisoria deve estar aberta e aguardar contagem inicial.');
      if (existing != null && !wasPending && pending) return conflictV2('CASH_SESSION_OPENING_IMMUTABLE', 'Fundo inicial confirmado nao pode voltar a provisório.');
      const storedPolicy = asRecord(storedOpening);
      const confirmsInitialFloat = existing?.status === 'open' && normalizedStatus === 'open' &&
        input.event.operation !== 'create' && wasPending && pendingFlag === false &&
        existing.deviceId === input.context.device.id && storedPolicy.version === opening.version &&
        storedPolicy.blindClosureEnabled === opening.blindClosureEnabled && storedPolicy.policyRevision === opening.policyRevision;
      if (wasPending && pendingFlag === false && !confirmsInitialFloat) return conflictV2('CASH_SESSION_OPENING_IMMUTABLE', 'Confirmacao exige sessao aberta no dispositivo e politica original.');
      if (storedOpening != null && !cashMetadataEqual(storedOpening, opening) && !confirmsInitialFloat) return conflictV2('CASH_SESSION_OPENING_IMMUTABLE', 'Contagem/politica de abertura imutavel.');
      if (confirmsInitialFloat) {
        const confirmationPermission = requireSyncPermission(input, 'cash.open', 'Voce nao tem permissao para confirmar fundo inicial.');
        if (confirmationPermission != null) return confirmationPermission;
      }
      if (normalizedStatus === 'closed' && pending) return invalidV2('Confirme o fundo inicial antes do fechamento.');
      if (existing?.deviceId != null && existing.deviceId !== input.context.device.id) return conflictV2('CASH_SESSION_DEVICE_MISMATCH', 'Sessao vinculada a outro dispositivo.');
      if (normalizedStatus === 'closed') {
        const parsedClosing = closingDetailsSchema.safeParse(closingRaw);
        if (!parsedClosing.success) return invalidV2('Contagem de fechamento V2 invalida.');
        closing = parsedClosing.data;
        if (closing.sessionUuid !== localUuid || closing.policyRevision !== opening.policyRevision || closing.blindClosureEnabled !== opening.blindClosureEnabled) return invalidV2('Fechamento diverge da sessao/politica de abertura.');
        if (closing.differenceCents !== closing.countedBalanceCents - closing.expectedBalanceCents || !validateCashV2Count(closing, closing.countedBalanceCents)) return invalidV2('Diferenca ou total da contagem invalido.');
        if ((closing.blindClosureEnabled || closing.differenceCents !== 0) && !closing.reason?.trim()) return invalidV2('Motivo de fechamento obrigatorio.');
        for (const [key, value] of Object.entries({ expectedBalanceCents: closing.expectedBalanceCents, closingBalanceCents: closing.countedBalanceCents, countedBalanceCents: closing.countedBalanceCents })) {
          if (input.payload[key] !== undefined && input.payload[key] !== value) return invalidV2('Saldo externo diverge do fechamento V2.');
        }
      } else if (closingRaw != null) return invalidV2('Sessao aberta nao pode conter fechamento.');
      if (existing?.status === 'closed') {
        if (!cashMetadataEqual(savedPayload.closingDetails, closing)) return conflictV2('CASH_SESSION_CLOSURE_IMMUTABLE', 'Fechamento original imutavel.');
        return { outcome: 'duplicate', entityServerId: existing.id };
      }
      // Serialize opens on the physical device without a partial index affecting legacy rows.
      if (existing == null && normalizedStatus === 'open') {
        await input.tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtext(${input.context.company.id}), hashtext(${input.context.device.id}))::text`;
        const active = await input.tx.cashSession.findFirst({ where: { companyId: input.context.company.id, deviceId: input.context.device.id, status: 'open' } });
        if (active != null) return conflictV2('CASH_SESSION_DEVICE_ALREADY_OPEN', 'Dispositivo ja possui caixa aberto.');
      }
    }

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

    const authorization = this.authorizeCashSessionChange({
      input,
      existing,
      requestedStatus: normalizedStatus,
    });
    if (authorization != null) {
      return authorization;
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
    if (v2) {
      mergedPayload.openingDetails = opening;
      if (closing != null) mergedPayload.closingDetails = closing;
      mergedPayload.cashMetadataVersion = 2;
      mergedPayload.awaitingInitialFloatConfirmation = input.payload.awaitingInitialFloatConfirmation ?? savedPayload.awaitingInitialFloatConfirmation ?? false;
    } else mergedPayload.cashMetadataVersion = 1;

    const data = {
      deviceId: existing?.deviceId ?? input.context.device.id,
      userId: existing?.userId ?? input.context.user.id,
      localId: firstIdentity(input.payload, ['localId', 'id']),
      status: normalizedStatus,
      openedAt,
      closedAt,
      openingBalanceCents:
        opening?.countedAmountCents ?? firstInt(input.payload, ['openingBalanceCents', 'initialFloatCents']) ??
        existing?.openingBalanceCents ??
        0,
      closingBalanceCents:
        closing?.countedBalanceCents ?? firstInt(input.payload, ['closingBalanceCents', 'countedBalanceCents']) ??
        existing?.closingBalanceCents,
      expectedBalanceCents:
        closing?.expectedBalanceCents ?? firstInt(input.payload, ['expectedBalanceCents']) ??
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

  private authorizeCashSessionChange(input: {
    input: SyncMaterializerInput;
    existing: ExistingCashSession | null;
    requestedStatus: 'open' | 'closed';
  }): SyncMaterializerResult | null {
    const { existing, requestedStatus } = input;
    const currentUserId = input.input.context.user.id;
    const isOwnSession = existing == null || existing.userId === currentUserId;

    if (requestedStatus === 'open') {
      if (!isOwnSession && !canManageOtherCashSessions(input.input)) {
        return {
          outcome: 'rejected',
          code: 'CASH_SESSION_OWNERSHIP_REQUIRED',
          message: 'Voce so pode alterar o seu proprio caixa.',
        };
      }

      return existing == null
        ? requireSyncPermission(
            input.input,
            'cash.open',
            'Voce nao tem permissao para abrir caixa.',
          )
        : null;
    }

    if (isOwnSession) {
      return requireSyncPermission(
        input.input,
        'cash.close',
        'Voce nao tem permissao para fechar caixa.',
      );
    }

    if (canManageOtherCashSessions(input.input)) {
      return null;
    }

    return {
      outcome: 'rejected',
      code: 'CASH_CLOSE_OTHER_FORBIDDEN',
      message: 'Voce nao tem permissao para fechar o caixa de outro funcionario.',
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
