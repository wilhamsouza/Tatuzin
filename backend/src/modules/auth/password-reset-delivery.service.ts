import { Resend } from 'resend';

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

export type PasswordResetDeliveryConfig = {
  APP_ENV: string;
  MAIL_FROM_AUTH: string | null;
  MAIL_REPLY_TO_SUPPORT: string | null;
  PASSWORD_RESET_APP_BASE_URL: string | null;
  PASSWORD_RESET_DEBUG_LOG_TOKEN: boolean;
  RESEND_API_KEY: string | null;
  isProduction: boolean;
};

export type PasswordResetDeliveryLogger = Pick<typeof logger, 'info' | 'error'>;

type ResendEmailClient = {
  emails: {
    send(payload: {
      from: string;
      to: string | string[];
      subject: string;
      html: string;
      text: string;
      replyTo?: string | string[];
    }): Promise<{
      data: {
        id: string;
      } | null;
      error: {
        message: string;
        name: string;
        statusCode: number | null;
      } | null;
    }>;
  };
};

type PasswordResetDeliveryDependencies = {
  config?: PasswordResetDeliveryConfig;
  logger?: PasswordResetDeliveryLogger;
  resendClient?: ResendEmailClient | null;
};

const defaultConfig: PasswordResetDeliveryConfig = {
  APP_ENV: env.APP_ENV,
  MAIL_FROM_AUTH: env.MAIL_FROM_AUTH,
  MAIL_REPLY_TO_SUPPORT: env.MAIL_REPLY_TO_SUPPORT,
  PASSWORD_RESET_APP_BASE_URL: env.PASSWORD_RESET_APP_BASE_URL,
  PASSWORD_RESET_DEBUG_LOG_TOKEN: env.PASSWORD_RESET_DEBUG_LOG_TOKEN,
  RESEND_API_KEY: env.RESEND_API_KEY,
  isProduction: env.isProduction,
};

export class ResendPasswordResetDeliveryService
  implements PasswordResetDeliveryService
{
  private readonly config: PasswordResetDeliveryConfig;
  private readonly deliveryLogger: PasswordResetDeliveryLogger;
  private readonly resendClient: ResendEmailClient | null;

  constructor(dependencies: PasswordResetDeliveryDependencies = {}) {
    this.config = dependencies.config ?? defaultConfig;
    this.deliveryLogger = dependencies.logger ?? logger;
    this.resendClient =
      dependencies.resendClient ?? this.createResendClient(this.config);
  }

  async sendResetToken(input: PasswordResetDeliveryInput) {
    const resetUrl = this.buildResetUrl(input.resetToken);
    const baseContext = {
      userId: input.userId,
      expiresAt: input.expiresAt,
    };

    if (this.canSendWithResend(resetUrl)) {
      const resendResetUrl = resetUrl!;
      const message = this.buildMessage(input, resendResetUrl);

      try {
        const response = await this.resendClient!.emails.send({
          from: this.config.MAIL_FROM_AUTH!,
          to: input.userEmail,
          subject: message.subject,
          html: message.html,
          text: message.text,
          ...(this.config.MAIL_REPLY_TO_SUPPORT == null
            ? {}
            : { replyTo: this.config.MAIL_REPLY_TO_SUPPORT }),
        });

        if (response.error != null) {
          this.deliveryLogger.error('auth.password_reset.delivery_failed', {
            ...baseContext,
            deliveryMode: 'resend',
            provider: 'resend',
            reason: 'provider_rejected',
            providerError: this.sanitizeProviderError(
              response.error,
              input.resetToken,
              resendResetUrl,
            ),
          });
        } else {
          this.deliveryLogger.info('auth.password_reset.delivery_sent', {
            ...baseContext,
            deliveryMode: this.isDebugTokenLoggingEnabled()
              ? 'resend_with_debug_log'
              : 'resend',
            provider: 'resend',
            providerMessageId: response.data?.id ?? null,
          });
        }
      } catch (error) {
        this.deliveryLogger.error('auth.password_reset.delivery_failed', {
          ...baseContext,
          deliveryMode: 'resend',
          provider: 'resend',
          reason: 'provider_request_failed',
          providerError: this.sanitizeUnexpectedProviderError(
            error,
            input.resetToken,
            resendResetUrl,
          ),
        });
      }
    } else {
      this.deliveryLogger.info('auth.password_reset.delivery_skipped', {
        ...baseContext,
        deliveryMode: this.isDebugTokenLoggingEnabled()
          ? 'debug_log'
          : 'not_configured',
        reason: this.resolveSkipReason(resetUrl),
      });
    }

    if (!this.isDebugTokenLoggingEnabled()) {
      return;
    }

    this.deliveryLogger.info('auth.password_reset.debug_delivery', {
      ...baseContext,
      userEmail: input.userEmail,
      userName: input.userName,
      resetToken: input.resetToken,
      resetUrl,
      deliveryMode: this.canSendWithResend(resetUrl)
        ? 'resend_with_debug_log'
        : 'debug_log',
    });
  }

  private canSendWithResend(resetUrl: string | null) {
    return (
      this.resendClient != null &&
      this.config.MAIL_FROM_AUTH != null &&
      resetUrl != null
    );
  }

  private createResendClient(config: PasswordResetDeliveryConfig) {
    if (config.RESEND_API_KEY == null) {
      return null;
    }

    return new Resend(config.RESEND_API_KEY);
  }

  private isDebugTokenLoggingEnabled() {
    return (
      this.config.PASSWORD_RESET_DEBUG_LOG_TOKEN &&
      !this.config.isProduction &&
      this.config.APP_ENV.trim().toLowerCase() === 'local-development'
    );
  }

  private buildResetUrl(resetToken: string) {
    const baseUrl = this.config.PASSWORD_RESET_APP_BASE_URL;
    if (baseUrl == null) {
      return null;
    }

    try {
      const url = new URL(baseUrl);
      url.searchParams.set('token', resetToken);
      return url.toString();
    } catch {
      return null;
    }
  }

  private buildMessage(input: PasswordResetDeliveryInput, resetUrl: string) {
    const greetingName = input.userName.trim();
    const greeting =
      greetingName.length > 0 ? `Ola, ${greetingName}.` : 'Ola,';
    const expirationNotice = this.formatExpirationNotice(input.expiresAt);
    const escapedGreeting = this.escapeHtml(greeting);
    const escapedResetUrl = this.escapeHtml(resetUrl);
    const escapedResetToken = this.escapeHtml(input.resetToken);

    return {
      subject: 'Redefina sua senha do Tatuzin',
      html: [
        '<div style="font-family: Arial, sans-serif; color: #111827; line-height: 1.6;">',
        `<p>${escapedGreeting}</p>`,
        '<p>Recebemos uma solicitacao para redefinir a senha da sua conta Tatuzin.</p>',
        '<p>',
        `<a href="${escapedResetUrl}" style="display: inline-block; padding: 12px 20px; border-radius: 8px; background-color: #111827; color: #ffffff; text-decoration: none; font-weight: 600;">Redefinir senha</a>`,
        '</p>',
        '<p>Se preferir, copie e cole este link no navegador:</p>',
        `<p><a href="${escapedResetUrl}">${escapedResetUrl}</a></p>`,
        '<p>Se o link nao abrir automaticamente no app, copie este token e cole na tela "Redefinir senha" do Tatuzin:</p>',
        `<p style="padding: 12px 16px; border-radius: 12px; background-color: #f3f4f6; font-family: 'Courier New', monospace; word-break: break-all;">${escapedResetToken}</p>`,
        `<p>${this.escapeHtml(expirationNotice)}</p>`,
        '<p>Se voce nao solicitou essa redefinicao, ignore este e-mail.</p>',
        '</div>',
      ].join(''),
      text: [
        greeting,
        '',
        'Recebemos uma solicitacao para redefinir a senha da sua conta Tatuzin.',
        'Abra o link abaixo para continuar:',
        resetUrl,
        '',
        'Se o link nao abrir automaticamente no app, copie este token e cole na tela "Redefinir senha" do Tatuzin:',
        input.resetToken,
        '',
        expirationNotice,
        'Se voce nao solicitou essa redefinicao, ignore este e-mail.',
      ].join('\n'),
    };
  }

  private formatExpirationNotice(expiresAt: Date) {
    const remainingMinutes = Math.max(
      1,
      Math.ceil((expiresAt.getTime() - Date.now()) / 60_000),
    );

    if (remainingMinutes === 1) {
      return 'Este link expira em aproximadamente 1 minuto.';
    }

    return `Este link expira em aproximadamente ${remainingMinutes} minutos.`;
  }

  private resolveSkipReason(resetUrl: string | null) {
    if (resetUrl == null) {
      return 'missing_password_reset_app_base_url';
    }

    if (this.config.MAIL_FROM_AUTH == null) {
      return 'missing_mail_from_auth';
    }

    if (this.resendClient == null) {
      return 'missing_resend_api_key';
    }

    return 'not_configured';
  }

  private sanitizeProviderError(
    error: {
      message: string;
      name: string;
      statusCode: number | null;
    },
    resetToken: string,
    resetUrl: string,
  ) {
    return {
      name: error.name,
      statusCode: error.statusCode,
      message: this.redactSensitiveText(error.message, resetToken, resetUrl),
    };
  }

  private sanitizeUnexpectedProviderError(
    error: unknown,
    resetToken: string,
    resetUrl: string,
  ) {
    if (error instanceof Error) {
      return {
        name: error.name,
        message: this.redactSensitiveText(error.message, resetToken, resetUrl),
      };
    }

    return {
      name: 'UnknownProviderError',
      message: 'Unexpected error while sending password reset email.',
    };
  }

  private redactSensitiveText(
    value: string,
    resetToken: string,
    resetUrl: string,
  ) {
    const sensitiveValues = [
      resetToken,
      encodeURIComponent(resetToken),
      resetUrl,
      this.config.RESEND_API_KEY,
    ].filter((candidate): candidate is string => candidate != null && candidate.length > 0);

    return sensitiveValues.reduce(
      (message, sensitiveValue) => message.split(sensitiveValue).join('[redacted]'),
      value,
    );
  }

  private escapeHtml(value: string) {
    return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
  }
}
