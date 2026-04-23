import type { Customer } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { toPaginationParams } from '../../shared/http/pagination';
import type {
  CustomerListQueryInput,
  CustomerUpsertInput,
} from './customers.schemas';

export class CustomersService {
  async listForCompany(companyId: string, query: CustomerListQueryInput) {
    const where = {
      companyId,
      ...(query.includeDeleted ? {} : { deletedAt: null }),
    };
    const { skip, take } = toPaginationParams({
      page: query.page,
      pageSize: query.pageSize,
    });

    const [total, customers] = await prisma.$transaction([
      prisma.customer.count({ where }),
      prisma.customer.findMany({
        where,
        skip,
        take,
        orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
      }),
    ]);

    return {
      items: customers.map((customer) => this.toCustomerDto(customer)),
      total,
    };
  }

  async getById(companyId: string, customerId: string) {
    const customer = await prisma.customer.findFirst({
      where: {
        id: customerId,
        companyId,
      },
    });

    if (!customer) {
      throw new AppError('Cliente nao encontrado.', 404, 'CUSTOMER_NOT_FOUND');
    }

    return this.toCustomerDto(customer);
  }

  async create(companyId: string, input: CustomerUpsertInput) {
    const customer = await prisma.customer.upsert({
      where: {
        companyId_localUuid: {
          companyId,
          localUuid: input.localUuid,
        },
      },
      update: this.toCreateOrUpdateData(companyId, input),
      create: this.toCreateOrUpdateData(companyId, input),
    });

    return this.toCustomerDto(customer);
  }

  async update(
    companyId: string,
    customerId: string,
    input: CustomerUpsertInput,
  ) {
    const existing = await prisma.customer.findFirst({
      where: {
        id: customerId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError('Cliente nao encontrado.', 404, 'CUSTOMER_NOT_FOUND');
    }

    await this.ensureLocalUuidAvailable(companyId, input.localUuid, customerId);

    const customer = await prisma.customer.update({
      where: { id: customerId },
      data: this.toCreateOrUpdateData(companyId, input),
    });

    return this.toCustomerDto(customer);
  }

  async softDelete(companyId: string, customerId: string) {
    const existing = await prisma.customer.findFirst({
      where: {
        id: customerId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError('Cliente nao encontrado.', 404, 'CUSTOMER_NOT_FOUND');
    }

    const customer = await prisma.customer.update({
      where: { id: customerId },
      data: {
        isActive: false,
        deletedAt: new Date(),
      },
    });

    return this.toCustomerDto(customer);
  }

  private async ensureLocalUuidAvailable(
    companyId: string,
    localUuid: string,
    currentId: string,
  ) {
    const conflicting = await prisma.customer.findFirst({
      where: {
        companyId,
        localUuid,
        id: { not: currentId },
      },
      select: { id: true },
    });

    if (conflicting) {
      throw new AppError(
        'Ja existe outro cliente remoto com este localUuid neste tenant.',
        409,
        'CUSTOMER_LOCAL_UUID_CONFLICT',
      );
    }
  }

  private toCreateOrUpdateData(companyId: string, input: CustomerUpsertInput) {
    return {
      companyId,
      localUuid: input.localUuid,
      name: input.name,
      phone: input.phone,
      address: input.address,
      notes: input.notes,
      isActive: input.deletedAt == null ? input.isActive : false,
      deletedAt: input.deletedAt,
    };
  }

  private toCustomerDto(customer: Customer) {
    return {
      id: customer.id,
      companyId: customer.companyId,
      localUuid: customer.localUuid,
      name: customer.name,
      phone: customer.phone,
      address: customer.address,
      notes: customer.notes,
      isActive: customer.isActive,
      deletedAt: customer.deletedAt?.toISOString() ?? null,
      createdAt: customer.createdAt.toISOString(),
      updatedAt: customer.updatedAt.toISOString(),
    };
  }
}
