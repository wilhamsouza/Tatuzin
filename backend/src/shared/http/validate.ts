import type { NextFunction, Request, Response } from 'express';
import type { ZodTypeAny } from 'zod';

export function validateBody<TSchema extends ZodTypeAny>(schema: TSchema) {
  return (request: Request, _response: Response, next: NextFunction) => {
    request.body = schema.parse(request.body);
    next();
  };
}

export function validateQuery<TSchema extends ZodTypeAny>(schema: TSchema) {
  return (request: Request, _response: Response, next: NextFunction) => {
    request.query = schema.parse(request.query);
    next();
  };
}
