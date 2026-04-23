import type { Supplier } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import type {
  SupplierListQueryInput,
  SupplierUpsertInput,
} from './suppliers.schemas';

export class SuppliersService {
  async listForCompany(companyId: string, query: SupplierListQueryInput) {
    const where = {
      companyId,
      ...(query.includeDeleted ? {} : { deletedAt: null }),
    };
    const { skip, take } = toPaginationParams({
      page: query.page,
      pageSize: query.pageSize,
    });

    const [total, suppliers] = await prisma.$transaction([
      prisma.supplier.count({ where }),
      prisma.supplier.findMany({
        where,
        skip,
        take,
        orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
      }),
    ]);

    return {
      items: suppliers.map((supplier) => this.toSupplierDto(supplier)),
      total,
    };
  }

  async getById(companyId: string, supplierId: string) {
    const supplier = await prisma.supplier.findFirst({
      where: {
        id: supplierId,
        companyId,
      },
    });

    if (!supplier) {
      throw new AppError(
        'Fornecedor nao encontrado.',
        404,
        'SUPPLIER_NOT_FOUND',
      );
    }

    return this.toSupplierDto(supplier);
  }

  async create(companyId: string, input: SupplierUpsertInput) {
    const existing = await prisma.supplier.findFirst({
      where: {
        companyId,
        localUuid: input.localUuid,
      },
    });

    if (existing) {
      const updated = await prisma.supplier.update({
        where: { id: existing.id },
        data: this.toCreateOrUpdateData(companyId, input),
      });
      return this.toSupplierDto(updated);
    }

    const supplier = await prisma.supplier.create({
      data: this.toCreateOrUpdateData(companyId, input),
    });

    return this.toSupplierDto(supplier);
  }

  async update(companyId: string, supplierId: string, input: SupplierUpsertInput) {
    const existing = await prisma.supplier.findFirst({
      where: {
        id: supplierId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError(
        'Fornecedor nao encontrado.',
        404,
        'SUPPLIER_NOT_FOUND',
      );
    }

    const supplier = await prisma.supplier.update({
      where: { id: supplierId },
      data: this.toCreateOrUpdateData(companyId, input),
    });

    return this.toSupplierDto(supplier);
  }

  async softDelete(companyId: string, supplierId: string) {
    const existing = await prisma.supplier.findFirst({
      where: {
        id: supplierId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError(
        'Fornecedor nao encontrado.',
        404,
        'SUPPLIER_NOT_FOUND',
      );
    }

    const supplier = await prisma.supplier.update({
      where: { id: supplierId },
      data: {
        isActive: false,
        deletedAt: new Date(),
      },
    });

    return this.toSupplierDto(supplier);
  }

  private toCreateOrUpdateData(companyId: string, input: SupplierUpsertInput) {
    return {
      companyId,
      localUuid: input.localUuid,
      name: input.name,
      tradeName: input.tradeName,
      phone: input.phone,
      email: input.email,
      address: input.address,
      document: input.document,
      contactPerson: input.contactPerson,
      notes: input.notes,
      isActive: input.deletedAt == null ? input.isActive : false,
      deletedAt: input.deletedAt,
    };
  }

  private toSupplierDto(supplier: Supplier) {
    return {
      id: supplier.id,
      companyId: supplier.companyId,
      localUuid: supplier.localUuid,
      name: supplier.name,
      tradeName: supplier.tradeName,
      phone: supplier.phone,
      email: supplier.email,
      address: supplier.address,
      document: supplier.document,
      contactPerson: supplier.contactPerson,
      notes: supplier.notes,
      isActive: supplier.isActive,
      deletedAt: supplier.deletedAt?.toISOString() ?? null,
      createdAt: supplier.createdAt.toISOString(),
      updatedAt: supplier.updatedAt.toISOString(),
    };
  }
}
