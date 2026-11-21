import { Router } from 'express';
import { requirePlatformAdmin } from '../../shared/http/auth-middleware';
import { asyncHandler } from '../../shared/http/async-handler';
import { validateBody, validateQuery } from '../../shared/http/validate';
import { supportCaseCreateSchema, supportCaseListSchema, supportCaseNoteSchema, supportCaseUpdateSchema, type SupportCaseListInput } from './admin-support-cases.schemas';
import { AdminSupportCasesService } from './admin-support-cases.service';

export const adminSupportCasesRouter = Router();
const service = new AdminSupportCasesService();
adminSupportCasesRouter.use(requirePlatformAdmin);
adminSupportCasesRouter.get('/', validateQuery(supportCaseListSchema), asyncHandler(async (request, response) => {
  response.json(await service.list(request.auth!.userId, request.query as unknown as SupportCaseListInput));
}));
adminSupportCasesRouter.get('/assignees', asyncHandler(async (request, response) => {
  const companyId = typeof request.query.companyId === 'string' ? request.query.companyId : undefined;
  response.json(await service.assignees(request.auth!.userId, companyId));
}));
adminSupportCasesRouter.post('/', validateBody(supportCaseCreateSchema), asyncHandler(async (request, response) => {
  const result = await service.create(request.auth!.userId, request.body);
  response.status(result.reused ? 200 : 201).json(result);
}));
adminSupportCasesRouter.get('/:id', asyncHandler(async (request, response) => {
  response.json(await service.detail(request.auth!.userId, String(request.params.id)));
}));
adminSupportCasesRouter.patch('/:id', validateBody(supportCaseUpdateSchema), asyncHandler(async (request, response) => {
  response.json(await service.update(request.auth!.userId, String(request.params.id), request.body));
}));
adminSupportCasesRouter.post('/:id/notes', validateBody(supportCaseNoteSchema), asyncHandler(async (request, response) => {
  response.json(await service.addNote(request.auth!.userId, String(request.params.id), request.body));
}));
