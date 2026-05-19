import { z } from 'zod';

const optionalText = (max: number, fieldLabel: string) =>
  z
    .string({
      invalid_type_error: `${fieldLabel} deve ser texto.`,
    })
    .max(max, `${fieldLabel} deve ter no maximo ${max} caracteres.`)
    .optional()
    .nullable();

export const companyReceiptSettingsPatchSchema = z
  .object({
    receiptDisplayName: optionalText(80, 'Nome no comprovante'),
    receiptDocument: optionalText(32, 'CPF/CNPJ'),
    receiptPhone: optionalText(32, 'Telefone/WhatsApp'),
    receiptAddress: optionalText(160, 'Endereco'),
    receiptFooterMessage: optionalText(160, 'Mensagem no rodape'),
    showDocumentOnReceipt: z.boolean().optional(),
    showPhoneOnReceipt: z.boolean().optional(),
    showAddressOnReceipt: z.boolean().optional(),
    showFooterMessageOnReceipt: z.boolean().optional(),
  })
  .strict();

export type CompanyReceiptSettingsPatchInput = z.infer<
  typeof companyReceiptSettingsPatchSchema
>;
