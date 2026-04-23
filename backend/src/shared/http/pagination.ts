import { z } from 'zod';

export const sortDirectionSchema = z.enum(['asc', 'desc']).default('desc');

export const booleanQuerySchema = z.preprocess((value) => {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value !== 'string') {
    return value;
  }

  const normalized = value.trim().toLowerCase();
  if (normalized === 'true') {
    return true;
  }
  if (normalized === 'false') {
    return false;
  }

  return value;
}, z.boolean());

export const paginationQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  pageSize: z.coerce.number().int().min(1).max(100).default(20),
});

export const includeDeletedQuerySchema = booleanQuerySchema.default(false);

export function createListQuerySchema(options?: { includeDeleted?: boolean }) {
  return paginationQuerySchema.extend(
    options?.includeDeleted === true
      ? {
          includeDeleted: includeDeletedQuerySchema,
        }
      : {},
  );
}

export type PaginationQuery = z.infer<typeof paginationQuerySchema>;

export function toPaginationParams(query: PaginationQuery) {
  return {
    skip: (query.page - 1) * query.pageSize,
    take: query.pageSize,
  };
}
