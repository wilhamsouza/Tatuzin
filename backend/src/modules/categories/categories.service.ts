import type { Category } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { CategoryUpsertInput } from './categories.schemas';

export class CategoriesService {
  async listForCompany(companyId: string, includeDeleted = false) {
    const categories = await prisma.category.findMany({
      where: {
        companyId,
        ...(includeDeleted ? {} : { deletedAt: null }),
      },
      orderBy: [{ updatedAt: 'desc' }, { name: 'asc' }],
    });

    return categories.map((category) => this.toCategoryDto(category));
  }

  async getById(companyId: string, categoryId: string) {
    const category = await prisma.category.findFirst({
      where: {
        id: categoryId,
        companyId,
      },
    });

    if (!category) {
      throw new AppError('Categoria nao encontrada.', 404, 'CATEGORY_NOT_FOUND');
    }

    return this.toCategoryDto(category);
  }

  async create(companyId: string, input: CategoryUpsertInput) {
    const category = await prisma.category.upsert({
      where: {
        companyId_localUuid: {
          companyId,
          localUuid: input.localUuid,
        },
      },
      update: this.toCreateOrUpdateData(companyId, input),
      create: this.toCreateOrUpdateData(companyId, input),
    });

    return this.toCategoryDto(category);
  }

  async update(companyId: string, categoryId: string, input: CategoryUpsertInput) {
    const existing = await prisma.category.findFirst({
      where: {
        id: categoryId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError('Categoria nao encontrada.', 404, 'CATEGORY_NOT_FOUND');
    }

    await this.ensureLocalUuidAvailable(companyId, input.localUuid, categoryId);

    const category = await prisma.category.update({
      where: { id: categoryId },
      data: this.toCreateOrUpdateData(companyId, input),
    });

    return this.toCategoryDto(category);
  }

  async softDelete(companyId: string, categoryId: string) {
    const existing = await prisma.category.findFirst({
      where: {
        id: categoryId,
        companyId,
      },
      select: { id: true },
    });

    if (!existing) {
      throw new AppError('Categoria nao encontrada.', 404, 'CATEGORY_NOT_FOUND');
    }

    const deletedAt = new Date();

    const category = await prisma.$transaction(async (tx) => {
      await tx.product.updateMany({
        where: {
          companyId,
          categoryId,
        },
        data: {
          categoryId: null,
        },
      });

      return tx.category.update({
        where: { id: categoryId },
        data: {
          isActive: false,
          deletedAt,
        },
      });
    });

    return this.toCategoryDto(category);
  }

  private async ensureLocalUuidAvailable(
    companyId: string,
    localUuid: string,
    currentId: string,
  ) {
    const conflicting = await prisma.category.findFirst({
      where: {
        companyId,
        localUuid,
        id: { not: currentId },
      },
      select: { id: true },
    });

    if (conflicting) {
      throw new AppError(
        'Ja existe outra categoria remota com este localUuid neste tenant.',
        409,
        'CATEGORY_LOCAL_UUID_CONFLICT',
      );
    }
  }

  private toCreateOrUpdateData(companyId: string, input: CategoryUpsertInput) {
    return {
      companyId,
      localUuid: input.localUuid,
      name: input.name,
      description: input.description,
      isActive: input.deletedAt == null ? input.isActive : false,
      deletedAt: input.deletedAt,
    };
  }

  private toCategoryDto(category: Category) {
    return {
      id: category.id,
      companyId: category.companyId,
      localUuid: category.localUuid,
      name: category.name,
      description: category.description,
      isActive: category.isActive,
      deletedAt: category.deletedAt?.toISOString() ?? null,
      createdAt: category.createdAt.toISOString(),
      updatedAt: category.updatedAt.toISOString(),
    };
  }
}
