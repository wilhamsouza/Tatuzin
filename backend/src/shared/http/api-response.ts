export type PaginationMeta = {
  page: number;
  pageSize: number;
  total: number;
  count: number;
  hasNext: boolean;
  hasPrevious: boolean;
};

export type PaginationInput<TItem> = {
  items: TItem[];
  page: number;
  pageSize: number;
  total: number;
};

export function buildPaginationMeta(
  input: PaginationInput<unknown>,
): PaginationMeta {
  const count = input.items.length;
  const totalPages =
    input.pageSize <= 0 ? 0 : Math.ceil(input.total / input.pageSize);

  return {
    page: input.page,
    pageSize: input.pageSize,
    total: input.total,
    count,
    hasNext: totalPages > 0 && input.page < totalPages,
    hasPrevious: input.page > 1,
  };
}

export function buildPaginatedResponse<TItem>(
  input: PaginationInput<TItem>,
): PaginationMeta & { items: TItem[] } {
  return {
    items: input.items,
    ...buildPaginationMeta(input),
  };
}
