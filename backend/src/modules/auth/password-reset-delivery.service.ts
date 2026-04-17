import { env } from '../../config/env';
import { logger } from '../../shared/observability/logger';

export type PasswordResetDeliveryInput = {
  userId: string;
  userEmail: string;
  userName: string;
  resetToken: string;
  expiresAt: Date;
};

export interface PasswordResetDeliveryService {
  sendResetToken(input: PasswordResetDeliveryInput): Promise<void>;
}

export class LoggingPasswordResetDeliveryService
  implements PasswordResetDeliveryService
{
  async sendResetToken(input: PasswordResetDeliveryInput) {
    const deliveryContext = {
      userId: input.userId,
      expiresAt: input.expiresAt,
      deliveryMode: this.isDebugTokenLoggingEnabled()
        ? 'debug_log'
        : 'not_configured',
    };

    if (!this.isDebugTokenLoggingEnabled()) {
      logger.info('auth.password_reset.delivery_skipped', deliveryContext);
      return;
    }

    logger.info('auth.password_reset.debug_delivery', {
      ...deliveryContext,
      userEmail: input.userEmail,
      userName: input.userName,
      resetToken: input.resetToken,
      resetUrl: this.buildResetUrl(input.resetToken),
    });
  }

  private isDebugTokenLoggingEnabled() {
    return (
      env.PASSWORD_RESET_DEBUG_LOG_TOKEN &&
      env.APP_ENV.trim().toLowerCase() !== 'production'
    );
  }

  private buildResetUrl(resetToken: string) {
    const baseUrl = env.PASSWORD_RESET_APP_BASE_URL;
    if (baseUrl == null) {
      return null;
    }

    const separator = baseUrl.includes('?') ? '&' : '?';
    return `${baseUrl}${separator}token=${encodeURIComponent(resetToken)}`;
  }
}
