import { prisma } from '../../database/prisma';

export class UsersService {
  async findByEmail(email: string) {
    return prisma.user.findUnique({
      where: { email: email.toLowerCase().trim() },
    });
  }

  async countUsers(): Promise<number> {
    return prisma.user.count();
  }
}
