import type { NextFunction, Request, RequestHandler, Response } from 'express';

import { AppError } from '../../shared/http/app-error';
import type { EmployeePermission } from './employee-permissions';
import { hasEmployeePermission } from './employee-permissions';

export function requireEmployeePermission(
  permission: EmployeePermission,
): RequestHandler {
  return (request: Request, _response: Response, next: NextFunction) => {
    const appContext = request.appContext;
    if (appContext == null) {
      next(
        new AppError(
          'Contexto de aplicativo ausente.',
          401,
          'APP_CONTEXT_REQUIRED',
        ),
      );
      return;
    }

    if (hasEmployeePermission(appContext.membership.permissions, permission)) {
      next();
      return;
    }

    next(
      new AppError(
        'Voce nao tem permissao para gerenciar funcionarios.',
        403,
        'EMPLOYEE_PERMISSION_REQUIRED',
        { permission },
      ),
    );
  };
}
