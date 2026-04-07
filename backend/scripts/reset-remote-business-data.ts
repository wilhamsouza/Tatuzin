import 'dotenv/config';

import { prisma } from '../src/database/prisma';

type CleanupSummary = {
  saleItems: number;
  fiadoPayments: number;
  financialEvents: number;
  cashEvents: number;
  sales: number;
  purchasePayments: number;
  purchaseItems: number;
  purchases: number;
  products: number;
  customers: number;
  suppliers: number;
  categories: number;
  adminAuditLogs: number;
};

type PreservedSummary = {
  users: number;
  companies: number;
  memberships: number;
  licenses: number;
  adminAuditLogs: number;
};

const LOCAL_DATABASE_HOSTS = new Set(['localhost', '127.0.0.1', '::1']);

function parseBooleanFlag(value: string | undefined): boolean {
  return value?.trim().toLowerCase() === 'true';
}

function readDatabaseHost(databaseUrl: string): string | null {
  try {
    return new URL(databaseUrl).hostname;
  } catch (_) {
    return null;
  }
}

async function collectCleanupSummary(): Promise<CleanupSummary> {
  const [
    saleItems,
    fiadoPayments,
    financialEvents,
    cashEvents,
    sales,
    purchasePayments,
    purchaseItems,
    purchases,
    products,
    customers,
    suppliers,
    categories,
    adminAuditLogs,
  ] = await Promise.all([
    prisma.saleItem.count(),
    prisma.fiadoPayment.count(),
    prisma.financialEvent.count(),
    prisma.cashEvent.count(),
    prisma.sale.count(),
    prisma.purchasePayment.count(),
    prisma.purchaseItem.count(),
    prisma.purchase.count(),
    prisma.product.count(),
    prisma.customer.count(),
    prisma.supplier.count(),
    prisma.category.count(),
    prisma.adminAuditLog.count(),
  ]);

  return {
    saleItems,
    fiadoPayments,
    financialEvents,
    cashEvents,
    sales,
    purchasePayments,
    purchaseItems,
    purchases,
    products,
    customers,
    suppliers,
    categories,
    adminAuditLogs,
  };
}

async function collectPreservedSummary(): Promise<PreservedSummary> {
  const [users, companies, memberships, licenses, adminAuditLogs] =
    await Promise.all([
      prisma.user.count(),
      prisma.company.count(),
      prisma.membership.count(),
      prisma.license.count(),
      prisma.adminAuditLog.count(),
    ]);

  return {
    users,
    companies,
    memberships,
    licenses,
    adminAuditLogs,
  };
}

function printCleanupPlan(
  cleanupSummary: CleanupSummary,
  preservedSummary: PreservedSummary,
  includeAdminAudit: boolean,
): void {
  console.log('Tatuzin backend reset remoto operacional (DEV/LOCAL)');
  console.log('');
  console.log('Serao removidos:');
  console.log(`- categorias remotas: ${cleanupSummary.categories}`);
  console.log(`- produtos remotos: ${cleanupSummary.products}`);
  console.log(`- clientes remotos: ${cleanupSummary.customers}`);
  console.log(`- fornecedores remotos: ${cleanupSummary.suppliers}`);
  console.log(`- compras remotas: ${cleanupSummary.purchases}`);
  console.log(`- itens de compra remotos: ${cleanupSummary.purchaseItems}`);
  console.log(
    `- pagamentos de compra remotos: ${cleanupSummary.purchasePayments}`,
  );
  console.log(`- vendas remotas: ${cleanupSummary.sales}`);
  console.log(`- itens de venda remotos: ${cleanupSummary.saleItems}`);
  console.log(
    `- eventos financeiros remotos: ${cleanupSummary.financialEvents}`,
  );
  console.log(`- eventos de caixa remotos: ${cleanupSummary.cashEvents}`);
  console.log(`- pagamentos de fiado remotos: ${cleanupSummary.fiadoPayments}`);
  if (includeAdminAudit) {
    console.log(
      `- auditoria administrativa: ${cleanupSummary.adminAuditLogs}`,
    );
  } else {
    console.log(
      `- auditoria administrativa: preservada (${cleanupSummary.adminAuditLogs})`,
    );
  }
  console.log('');
  console.log('Serao preservados:');
  console.log(`- usuarios: ${preservedSummary.users}`);
  console.log(`- empresas: ${preservedSummary.companies}`);
  console.log(`- memberships: ${preservedSummary.memberships}`);
  console.log(`- licencas: ${preservedSummary.licenses}`);
}

async function main(): Promise<void> {
  if (process.env.NODE_ENV === 'production') {
    throw new Error(
      'Abortado: este script nao pode ser executado com NODE_ENV=production.',
    );
  }

  if (!parseBooleanFlag(process.env.ALLOW_REMOTE_BUSINESS_RESET)) {
    throw new Error(
      'Abortado: defina ALLOW_REMOTE_BUSINESS_RESET=true para confirmar conscientemente a limpeza.',
    );
  }

  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    throw new Error('Abortado: DATABASE_URL nao foi encontrado no ambiente.');
  }

  const databaseHost = readDatabaseHost(databaseUrl);
  const allowNonLocalReset = parseBooleanFlag(
    process.env.ALLOW_NON_LOCAL_DATABASE_RESET,
  );
  if (
    databaseHost == null ||
    (!LOCAL_DATABASE_HOSTS.has(databaseHost) && !allowNonLocalReset)
  ) {
    throw new Error(
      'Abortado: o script so permite limpeza em banco local por padrao. Use ALLOW_NON_LOCAL_DATABASE_RESET=true apenas se voce tiver certeza absoluta.',
    );
  }

  const includeAdminAudit = parseBooleanFlag(process.env.CLEAN_ADMIN_AUDIT);

  await prisma.$connect();

  const cleanupSummary = await collectCleanupSummary();
  const preservedBefore = await collectPreservedSummary();

  printCleanupPlan(cleanupSummary, preservedBefore, includeAdminAudit);
  console.log('');
  console.log('Executando limpeza...');

  const deletedCounts = await prisma.$transaction(async (tx) => {
    const deletedSaleItems = await tx.saleItem.deleteMany();
    const deletedFiadoPayments = await tx.fiadoPayment.deleteMany();
    const deletedFinancialEvents = await tx.financialEvent.deleteMany();
    const deletedCashEvents = await tx.cashEvent.deleteMany();
    const deletedSales = await tx.sale.deleteMany();
    const deletedPurchasePayments = await tx.purchasePayment.deleteMany();
    const deletedPurchaseItems = await tx.purchaseItem.deleteMany();
    const deletedPurchases = await tx.purchase.deleteMany();
    const deletedProducts = await tx.product.deleteMany();
    const deletedCustomers = await tx.customer.deleteMany();
    const deletedSuppliers = await tx.supplier.deleteMany();
    const deletedCategories = await tx.category.deleteMany();
    const deletedAdminAuditLogs = includeAdminAudit
      ? await tx.adminAuditLog.deleteMany()
      : { count: 0 };

    return {
      saleItems: deletedSaleItems.count,
      fiadoPayments: deletedFiadoPayments.count,
      financialEvents: deletedFinancialEvents.count,
      cashEvents: deletedCashEvents.count,
      sales: deletedSales.count,
      purchasePayments: deletedPurchasePayments.count,
      purchaseItems: deletedPurchaseItems.count,
      purchases: deletedPurchases.count,
      products: deletedProducts.count,
      customers: deletedCustomers.count,
      suppliers: deletedSuppliers.count,
      categories: deletedCategories.count,
      adminAuditLogs: deletedAdminAuditLogs.count,
    };
  });

  const preservedAfter = await collectPreservedSummary();
  const cleanupAfter = await collectCleanupSummary();

  console.log('');
  console.log('Limpeza concluida com sucesso.');
  console.log('');
  console.log('Resumo removido:');
  console.log(`- categorias: ${deletedCounts.categories}`);
  console.log(`- produtos: ${deletedCounts.products}`);
  console.log(`- clientes: ${deletedCounts.customers}`);
  console.log(`- fornecedores: ${deletedCounts.suppliers}`);
  console.log(`- compras: ${deletedCounts.purchases}`);
  console.log(`- itens_compra: ${deletedCounts.purchaseItems}`);
  console.log(`- compra_pagamentos: ${deletedCounts.purchasePayments}`);
  console.log(`- vendas: ${deletedCounts.sales}`);
  console.log(`- itens_venda: ${deletedCounts.saleItems}`);
  console.log(`- eventos_financeiros: ${deletedCounts.financialEvents}`);
  console.log(`- eventos_caixa: ${deletedCounts.cashEvents}`);
  console.log(`- fiado_pagamentos: ${deletedCounts.fiadoPayments}`);
  if (includeAdminAudit) {
    console.log(`- admin_audit_logs: ${deletedCounts.adminAuditLogs}`);
  }
  console.log('');
  console.log('Camada preservada:');
  console.log(`- users preservados: ${preservedAfter.users}`);
  console.log(`- companies preservadas: ${preservedAfter.companies}`);
  console.log(`- memberships preservadas: ${preservedAfter.memberships}`);
  console.log(`- licenses preservadas: ${preservedAfter.licenses}`);
  console.log(
    `- admin audit preservada: ${includeAdminAudit ? 'nao' : 'sim'} (${preservedAfter.adminAuditLogs})`,
  );
  console.log('');
  console.log('Estado operacional apos limpeza:');
  console.log(`- categorias restantes: ${cleanupAfter.categories}`);
  console.log(`- produtos restantes: ${cleanupAfter.products}`);
  console.log(`- clientes restantes: ${cleanupAfter.customers}`);
  console.log(`- fornecedores restantes: ${cleanupAfter.suppliers}`);
  console.log(`- compras restantes: ${cleanupAfter.purchases}`);
  console.log(`- vendas restantes: ${cleanupAfter.sales}`);
  console.log(
    `- eventos financeiros restantes: ${cleanupAfter.financialEvents}`,
  );
  console.log(`- eventos de caixa restantes: ${cleanupAfter.cashEvents}`);
}

main()
  .catch((error) => {
    console.error('');
    console.error(
      error instanceof Error
        ? error.message
        : 'Falha inesperada durante a limpeza remota operacional.',
    );
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
