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

export type SortMeta = {
  by: string;
  direction: 'asc' | 'desc';
};

export type AdminListResponseInput<
  TItem,
  TFilters extends Record<string, unknown>,
  TOverview extends Record<string, unknown> | undefined = undefined,
  TCapabilities extends Record<string, unknown> | undefined = undefined,
> = PaginationInput<TItem> & {
  filters: TFilters;
  sort?: SortMeta | null;
  overview?: TOverview;
  capabilities?: TCapabilities;
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

export function buildAdminListResponse<
  TItem,
  TFilters extends Record<string, unknown>,
  TOverview extends Record<string, unknown> | undefined = undefined,
  TCapabilities extends Record<string, unknown> | undefined = undefined,
>(
  input: AdminListResponseInput<TItem, TFilters, TOverview, TCapabilities>,
) {
  const pagination = buildPaginationMeta(input);

  return {
    items: input.items,
    pagination,
    filters: input.filters,
    sort: input.sort ?? null,
    ...(input.overview == null ? {} : { overview: input.overview }),
    ...(input.capabilities == null ? {} : { capabilities: input.capabilities }),
  };
}
