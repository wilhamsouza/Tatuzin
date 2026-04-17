import bcrypt from 'bcryptjs';

import { prisma } from '../src/database/prisma';

const INITIAL_TRIAL_DURATION_DAYS = 15;

async function main() {
  const email = 'admin@simples.local';
  const companySlug = 'empresa-demo-saas';
  const passwordHash = await bcrypt.hash('123456', 10);

  await prisma.$transaction(async (transaction) => {
    const startsAt = new Date();
    const expiresAt = new Date(
      startsAt.getTime() +
        INITIAL_TRIAL_DURATION_DAYS * 24 * 60 * 60 * 1000,
    );

    const company = await transaction.company.upsert({
      where: {
        slug: companySlug,
      },
      update: {
        name: 'Empresa Demo SaaS',
        legalName: 'Empresa Demo SaaS LTDA',
        documentNumber: '00.000.000/0001-00',
      },
      create: {
        name: 'Empresa Demo SaaS',
        legalName: 'Empresa Demo SaaS LTDA',
        documentNumber: '00.000.000/0001-00',
        slug: companySlug,
      },
    });

    await transaction.license.upsert({
      where: {
        companyId: company.id,
      },
      update: {
        plan: 'trial',
        status: 'TRIAL',
        syncEnabled: true,
        startsAt,
        expiresAt,
      },
      create: {
        companyId: company.id,
        plan: 'trial',
        status: 'TRIAL',
        startsAt,
        expiresAt,
        syncEnabled: true,
      },
    });

    const user = await transaction.user.upsert({
      where: {
        email,
      },
      update: {
        passwordHash,
        name: 'Administrador Local',
        isPlatformAdmin: false,
      },
      create: {
        email,
        passwordHash,
        name: 'Administrador Local',
        isPlatformAdmin: false,
      },
    });

    await transaction.membership.updateMany({
      where: {
        userId: user.id,
      },
      data: {
        isDefault: false,
      },
    });

    await transaction.membership.upsert({
      where: {
        userId_companyId: {
          userId: user.id,
          companyId: company.id,
        },
      },
      update: {
        role: 'OWNER',
        isDefault: true,
      },
      create: {
        userId: user.id,
        companyId: company.id,
        role: 'OWNER',
        isDefault: true,
      },
    });
  });

  console.log('Seed concluida com usuario local admin@simples.local / 123456');
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
