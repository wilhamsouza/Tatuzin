import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';

export class CompaniesService {
  async getCurrentCompanyForMembership(membershipId: string) {
    const membership = await prisma.membership.findUnique({
      where: { id: membershipId },
      include: {
        company: {
          include: {
            license: true,
          },
        },
      },
    });

    if (!membership?.company) {
      throw new AppError(
        'Empresa ativa nao encontrada para a sessao atual.',
        404,
        'COMPANY_NOT_FOUND',
      );
    }

    return membership.company;
  }
}
