import type { Company } from '@prisma/client';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { AppContext } from './app-context.types';
import type { CompanyReceiptSettingsPatchInput } from './company-settings.schemas';

export class CompanySettingsService {
  async getReceiptSettings(context: AppContext) {
    const company = await this.requireCompany(context.company.id);
    return { company: this.toCompanyReceiptSettingsDto(company) };
  }

  async updateReceiptSettings(
    context: AppContext,
    input: CompanyReceiptSettingsPatchInput,
  ) {
    this.assertCanUpdateCompanySettings(context);

    const company = await prisma.company.update({
      where: { id: context.company.id },
      data: {
        ...(input.receiptDisplayName === undefined
          ? {}
          : { receiptDisplayName: this.cleanOptionalText(input.receiptDisplayName) }),
        ...(input.receiptDocument === undefined
          ? {}
          : { receiptDocument: this.cleanOptionalText(input.receiptDocument) }),
        ...(input.receiptPhone === undefined
          ? {}
          : { receiptPhone: this.cleanOptionalText(input.receiptPhone) }),
        ...(input.receiptAddress === undefined
          ? {}
          : { receiptAddress: this.cleanOptionalText(input.receiptAddress) }),
        ...(input.receiptFooterMessage === undefined
          ? {}
          : {
              receiptFooterMessage: this.cleanOptionalText(
                input.receiptFooterMessage,
              ),
            }),
        ...(input.showDocumentOnReceipt === undefined
          ? {}
          : { showDocumentOnReceipt: input.showDocumentOnReceipt }),
        ...(input.showPhoneOnReceipt === undefined
          ? {}
          : { showPhoneOnReceipt: input.showPhoneOnReceipt }),
        ...(input.showAddressOnReceipt === undefined
          ? {}
          : { showAddressOnReceipt: input.showAddressOnReceipt }),
        ...(input.showFooterMessageOnReceipt === undefined
          ? {}
          : { showFooterMessageOnReceipt: input.showFooterMessageOnReceipt }),
      },
    });

    return { company: this.toCompanyReceiptSettingsDto(company) };
  }

  toCompanyReceiptSettingsDto(company: Pick<
    Company,
    | 'id'
    | 'name'
    | 'legalName'
    | 'documentNumber'
    | 'receiptDisplayName'
    | 'receiptDocument'
    | 'receiptPhone'
    | 'receiptAddress'
    | 'receiptFooterMessage'
    | 'showDocumentOnReceipt'
    | 'showPhoneOnReceipt'
    | 'showAddressOnReceipt'
    | 'showFooterMessageOnReceipt'
  >) {
    return {
      id: company.id,
      name: company.name,
      legalName: company.legalName,
      documentNumber: company.documentNumber,
      receiptDisplayName: company.receiptDisplayName,
      receiptDocument: company.receiptDocument,
      receiptPhone: company.receiptPhone,
      receiptAddress: company.receiptAddress,
      receiptFooterMessage: company.receiptFooterMessage,
      showDocumentOnReceipt: company.showDocumentOnReceipt,
      showPhoneOnReceipt: company.showPhoneOnReceipt,
      showAddressOnReceipt: company.showAddressOnReceipt,
      showFooterMessageOnReceipt: company.showFooterMessageOnReceipt,
    };
  }

  private async requireCompany(companyId: string) {
    const company = await prisma.company.findUnique({
      where: { id: companyId },
    });
    if (company == null) {
      throw new AppError('Empresa nao encontrada.', 404, 'COMPANY_NOT_FOUND');
    }
    return company;
  }

  private assertCanUpdateCompanySettings(context: AppContext) {
    const role = context.membership.role.trim().toUpperCase();
    if (role === 'OWNER' || role === 'ADMIN') {
      return;
    }

    throw new AppError(
      'Somente o dono/administrador pode alterar dados da empresa.',
      403,
      'COMPANY_SETTINGS_FORBIDDEN',
    );
  }

  private cleanOptionalText(value: string | null | undefined) {
    const normalized = value?.trim().replace(/\s+/g, ' ');
    return normalized == null || normalized.length === 0 ? null : normalized;
  }
}
