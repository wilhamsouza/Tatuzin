export class AppError extends Error {
  constructor(
    message: string,
    readonly statusCode = 400,
    readonly code = 'APP_ERROR',
    readonly details?: unknown,
    readonly headers?: Record<string, string>,
    readonly responseDetails?: unknown,
  ) {
    super(message);
    this.name = 'AppError';
  }
}
