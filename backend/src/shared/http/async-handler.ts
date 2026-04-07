import type { NextFunction, Request, RequestHandler, Response } from 'express';

export function asyncHandler(
  callback: (
    request: Request,
    response: Response,
    next: NextFunction,
  ) => Promise<unknown>,
): RequestHandler {
  return (request, response, next) => {
    void callback(request, response, next).catch(next);
  };
}
