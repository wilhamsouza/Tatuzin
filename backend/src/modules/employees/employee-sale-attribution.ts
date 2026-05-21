export type SaleAttributionInput = {
  convertedOperationalOrder?: { sellerUserId: string | null } | null;
  cashSession?: { userId: string | null } | null;
};

export type SaleSyncEventAttribution = {
  userId: string | null;
  occurredAt: Date;
};

export function resolveSaleActorUserId(
  sale: SaleAttributionInput,
  event: SaleSyncEventAttribution | null | undefined,
) {
  return (
    sale.convertedOperationalOrder?.sellerUserId ??
    event?.userId ??
    sale.cashSession?.userId ??
    null
  );
}
