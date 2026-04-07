import bcrypt from 'bcryptjs';

import { prisma } from '../src/database/prisma';

async function main() {
  const email = 'admin@simples.local';
  const existingUser = await prisma.user.findUnique({ where: { email } });

  if (existingUser) {
    console.log('Seed ja aplicada.');
    return;
  }

  const passwordHash = await bcrypt.hash('123456', 10);

  const company = await prisma.company.create({
    data: {
      name: 'Empresa Demo SaaS',
      legalName: 'Empresa Demo SaaS LTDA',
      documentNumber: '00.000.000/0001-00',
      slug: 'empresa-demo-saas',
    },
  });

  const user = await prisma.user.create({
    data: {
      email,
      passwordHash,
      name: 'Administrador Local',
    },
  });

  await prisma.membership.create({
    data: {
      userId: user.id,
      companyId: company.id,
      role: 'OWNER',
      isDefault: true,
    },
  });

  console.log('Seed concluida com usuario admin@simples.local / 123456');
}

main()
  .catch((error) => {
    console.error(error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
