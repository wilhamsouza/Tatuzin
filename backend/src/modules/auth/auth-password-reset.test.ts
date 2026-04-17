import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { after, before, beforeEach, describe, it } from 'node:test';

import bcrypt from 'bcryptjs';

import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import { AuthService } from './auth.service';
import type {
  PasswordResetDeliveryInput,
  PasswordResetDeliveryService,
} from './password-reset-delivery.service';

const runId = `pwd-reset-${Date.now()}`;
const baseClientPayload = {
  clientType: 'admin_web' as const,
  clientInstanceId: `${runId}-web`,
  deviceLabel: 'Password Reset Test Browser',
  platform: 'node-test',
  appVersion: 'password-reset-tests',
};

const initialPassword = 'OldPassword123!';
const replacementPassword = 'NewPassword123!';

describe('auth password reset flow', () => {
  before(async () => {
    await prisma.$connect();
  });

  beforeEach(async () => {
    await cleanupFixtures();
  });

  after(async () => {
    await cleanupFixtures();
    await prisma.$disconnect();
  });

  it('forgot-password returns a neutral response for an existing e-mail', async () => {
    const fixture = await createFixture('forgot-existing');
    const delivery = new CapturingPasswordResetDeliveryService();
    const service = new AuthService(undefined, delivery);

    const response = await service.forgotPassword({
      email: `  ${fixture.email.toUpperCase()}  `,
    });

    assert.equal(
      response.message,
      'Se existir uma conta com este e-mail, enviaremos as instrucoes para redefinir sua senha.',
    );
    assert.equal(delivery.deliveries.length, 1);
    assert.equal(delivery.deliveries[0]?.userEmail, fixture.email);

    const tokens = await prisma.passwordResetToken.findMany({
      where: {
        userId: fixture.userId,
      },
    });
    assert.equal(tokens.length, 1);
    assert.equal(tokens[0]?.consumedAt, null);
  });

  it('forgot-password returns the same neutral response for a non-existing e-mail', async () => {
    const delivery = new CapturingPasswordResetDeliveryService();
    const service = new AuthService(undefined, delivery);

    const response = await service.forgotPassword({
      email: `${runId}.missing@tatuzin.test`,
    });

    assert.equal(
      response.message,
      'Se existir uma conta com este e-mail, enviaremos as instrucoes para redefinir sua senha.',
    );
    assert.equal(delivery.deliveries.length, 0);

    const tokenCount = await prisma.passwordResetToken.count();
    assert.equal(tokenCount, 0);
  });

  it('reset-password accepts a valid token, updates the password and revokes old sessions', async () => {
    const fixture = await createFixture('reset-valid');
    const delivery = new CapturingPasswordResetDeliveryService();
    const service = new AuthService(undefined, delivery);

    const login = await service.login({
      email: fixture.email,
      password: initialPassword,
      ...baseClientPayload,
    });

    await service.forgotPassword({
      email: fixture.email,
    });

    const resetToken = delivery.lastResetToken();
    assert.ok(resetToken);

    const response = await service.resetPassword({
      token: resetToken,
      newPassword: replacementPassword,
    });

    assert.equal(
      response.message,
      'Sua senha foi redefinida com sucesso. Entre novamente para continuar.',
    );

    const updatedUser = await prisma.user.findUniqueOrThrow({
      where: { id: fixture.userId },
      select: {
        passwordHash: true,
      },
    });
    assert.equal(
      await bcrypt.compare(replacementPassword, updatedUser.passwordHash),
      true,
    );

    await assert.rejects(
      () =>
        service.login({
          email: fixture.email,
          password: initialPassword,
          ...baseClientPayload,
        }),
      (error: unknown) =>
        error instanceof AppError && error.code === 'INVALID_CREDENTIALS',
    );

    const relogin = await service.login({
      email: fixture.email,
      password: replacementPassword,
      ...baseClientPayload,
    });
    assert.ok(relogin.accessToken.length > 20);

    await assert.rejects(
      () =>
        service.refresh({
          refreshToken: login.refreshToken,
          ...baseClientPayload,
        }),
      (error: unknown) =>
        error instanceof AppError && error.code === 'SESSION_REVOKED',
    );
  });

  it('reset-password rejects an invalid token', async () => {
    const service = new AuthService(
      undefined,
      new CapturingPasswordResetDeliveryService(),
    );

    await assert.rejects(
      () =>
        service.resetPassword({
          token: 'invalid-reset-token-value-1234567890',
          newPassword: replacementPassword,
        }),
      (error: unknown) =>
        error instanceof AppError &&
        error.code === 'PASSWORD_RESET_TOKEN_INVALID',
    );
  });

  it('reset-password rejects an expired token', async () => {
    const fixture = await createFixture('reset-expired');
    const service = new AuthService(
      undefined,
      new CapturingPasswordResetDeliveryService(),
    );
    const expiredToken = 'expired-reset-token-value-123456789012345';

    await prisma.passwordResetToken.create({
      data: {
        userId: fixture.userId,
        tokenHash: hashToken(expiredToken),
        expiresAt: new Date(Date.now() - 60_000),
      },
    });

    await assert.rejects(
      () =>
        service.resetPassword({
          token: expiredToken,
          newPassword: replacementPassword,
        }),
      (error: unknown) =>
        error instanceof AppError &&
        error.code === 'PASSWORD_RESET_TOKEN_EXPIRED',
    );
  });

  it('reset-password tokens are not reusable', async () => {
    const fixture = await createFixture('reset-reuse');
    const delivery = new CapturingPasswordResetDeliveryService();
    const service = new AuthService(undefined, delivery);

    await service.forgotPassword({
      email: fixture.email,
    });

    const resetToken = delivery.lastResetToken();
    assert.ok(resetToken);

    await service.resetPassword({
      token: resetToken,
      newPassword: replacementPassword,
    });

    await assert.rejects(
      () =>
        service.resetPassword({
          token: resetToken,
          newPassword: 'AnotherPassword123!',
        }),
      (error: unknown) =>
        error instanceof AppError &&
        error.code === 'PASSWORD_RESET_TOKEN_ALREADY_USED',
    );
  });
});

class CapturingPasswordResetDeliveryService
  implements PasswordResetDeliveryService
{
  readonly deliveries: PasswordResetDeliveryInput[] = [];

  async sendResetToken(input: PasswordResetDeliveryInput) {
    this.deliveries.push(input);
  }

  lastResetToken() {
    return this.deliveries.at(-1)?.resetToken ?? '';
  }
}

async function createFixture(label: string) {
  const email = `${runId}.${label}@tatuzin.test`;
  const passwordHash = await bcrypt.hash(initialPassword, 10);
  const company = await prisma.company.create({
    data: {
      name: `Tatuzin ${label}`,
      legalName: `Tatuzin ${label} LTDA`,
      slug: `${runId}-${label}`,
    },
  });
  const user = await prisma.user.create({
    data: {
      email,
      name: `Tatuzin ${label} User`,
      passwordHash,
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

  return {
    userId: user.id,
    email,
  };
}

async function cleanupFixtures() {
  await prisma.user.deleteMany({
    where: {
      email: {
        startsWith: runId,
      },
    },
  });

  await prisma.company.deleteMany({
    where: {
      slug: {
        startsWith: runId,
      },
    },
  });
}

function hashToken(token: string) {
  return createHash('sha256').update(token).digest('hex');
}
