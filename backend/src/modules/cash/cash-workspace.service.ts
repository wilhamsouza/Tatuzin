import { randomUUID } from 'node:crypto';
import type { CashSession, Prisma } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../../database/prisma';
import { AppError } from '../../shared/http/app-error';
import type { AppContext } from '../app/app-context.types';
import { hasEmployeePermission } from '../employees/employee-permissions';
import { asRecord, firstString } from '../sync/materializers/payload-utils';
import { cashMetadataEqual, validateCashV2Count } from '../sync/materializers/cash-session-v2';
import { canReviewCash } from './cash-divergence-review.service';

const cents=z.number().int().min(0).max(2147483647);
const signedCents=z.number().int().min(-2147483648).max(2147483647);
const countFields={denominations:z.array(z.object({valueCents:cents.positive(),quantity:cents})).max(100).optional(),coinsCents:cents.optional()};
export const workspaceOpenSchema=z.object({requestId:z.string().uuid(),openingBalanceCents:cents,...countFields}).strict();
export const workspaceJoinSchema=z.object({requestId:z.string().uuid()}).strict();
export const workspaceCloseSchema=z.object({requestId:z.string().uuid(),expectedRevision:cents,countedBalanceCents:cents,localExpectedBalanceCents:signedCents.nullable().optional(),reason:z.string().trim().max(500).optional(),notes:z.string().trim().max(2000).optional(),...countFields}).strict();
export const workspaceAckSchema=z.object({generation:cents.positive(),revision:cents,drained:z.literal(true)}).strict();
const activeStates=['PENDING_SYNC','REVIEW_REQUIRED'];
type Tx=Prisma.TransactionClient;
type CloseInput=z.infer<typeof workspaceCloseSchema>;

function deny(message:string,code='CASH_WORKSPACE_FORBIDDEN',status=403):never {throw new AppError(message,status,code);}
function permission(context:AppContext,key:'cash.open'|'cash.close') {
 if (!hasEmployeePermission(context.membership.permissions,key)) deny('Sem permissao para operar caixa.');
}
async function device(tx:Tx,context:AppContext) {
 const row=await tx.companyDevice.findFirst({where:{id:context.device.id,companyId:context.company.id,status:'ACTIVE'}});
 if (!row) deny('Dispositivo ativo da empresa obrigatorio.','CASH_DEVICE_REQUIRED');
}
export async function lockCashWorkspaceSession(tx:Tx,sessionId:string,companyId:string) {
 await tx.$queryRaw`SELECT "id" FROM "CashSession" WHERE "id"=${sessionId} AND "companyId"=${companyId} FOR UPDATE`;
 return tx.cashSession.findFirst({where:{id:sessionId,companyId}});
}
async function ownSession(tx:Tx,context:AppContext,uuid:string,participant=true) {
 const found=await tx.cashSession.findFirst({where:{companyId:context.company.id,localUuid:uuid,workspaceVersion:3}});
 if (!found) deny('Caixa do funcionario nao encontrado.','CASH_WORKSPACE_NOT_FOUND',404);
 const session=await lockCashWorkspaceSession(tx,found.id,context.company.id);
 if (!session || session.userId!==context.user.id) deny('Caixa pertence a outro funcionario.','CASH_WORKSPACE_ACTOR_MISMATCH');
 await device(tx,context);
 if (participant && !await tx.cashWorkspaceParticipant.findUnique({where:{sessionId_deviceId:{sessionId:session.id,deviceId:context.device.id}}})) deny('Conecte este aparelho ao caixa antes de operar offline.','CASH_PARTICIPATION_REQUIRED');
 return session;
}
export async function cashWorkspaceExpected(tx:Tx,session:CashSession) {
 const events=await tx.cashEvent.findMany({where:{companyId:session.companyId,cashSessionId:session.id}});
 return cashWorkspaceLedgerExpected(session.openingBalanceCents,events);
}
export function cashWorkspaceLedgerExpected(openingBalanceCents:number,events:Array<{paymentMethod:string|null;eventType:string;amountCents:number}>) {
 let total=openingBalanceCents;
 for (const event of events) {
  const method=event.paymentMethod?.trim().toLowerCase();
  const physical=method==='dinheiro'||method==='cash'||(method==null&&['sangria','suprimento','ajuste','retirada','saida','entrada','adjustment','supply','withdrawal','cash_withdrawal'].includes(event.eventType));
  if (!physical) continue;
  total+=['saida','retirada','withdrawal','sangria','cash_withdrawal'].includes(event.eventType)?-Math.abs(event.amountCents):event.amountCents;
 }
 if (!Number.isSafeInteger(total)||total < -2147483648||total>2147483647) deny('Saldo fora do limite suportado.','CASH_BALANCE_OUT_OF_RANGE',422);
 return total;
}
export async function invalidateCashWorkspaceClosure(tx:Tx,session:CashSession,incrementRevision=true) {
 const revision=session.workspaceRevision+(incrementRevision?1:0);
 const pending=await tx.cashClosureRequest.findFirst({where:{sessionId:session.id,status:{in:activeStates}},orderBy:{generation:'desc'}});
 const generation=session.workspaceClosureGeneration+(pending?1:0);
 await tx.cashSession.update({where:{id:session.id},data:{workspaceRevision:revision,workspaceClosureGeneration:generation}});
 if (!pending) return;
 const expected=await cashWorkspaceExpected(tx,session);
 await tx.cashClosureRequest.update({where:{id:pending.id},data:{generation,ledgerRevision:revision,expectedBalanceCents:expected,differenceCents:pending.countedBalanceCents-expected,status:pending.status==='REVIEW_REQUIRED'||expected!==pending.expectedBalanceCents?'REVIEW_REQUIRED':'PENDING_SYNC'}});
}
async function attach(tx:Tx,session:CashSession,context:AppContext) {
 const existing=await tx.cashWorkspaceParticipant.findUnique({where:{sessionId_deviceId:{sessionId:session.id,deviceId:context.device.id}}});
 if (existing) return;
 await tx.cashWorkspaceParticipant.create({data:{companyId:context.company.id,sessionId:session.id,userId:context.user.id,deviceId:context.device.id}});
 await invalidateCashWorkspaceClosure(tx,session,false);
}
function originalPolicy(session:CashSession) {
 const opening=asRecord(asRecord(session.payload).openingDetails);
 return {blindClosureEnabled:opening.blindClosureEnabled===true,policyRevision:typeof opening.policyRevision==='number'?opening.policyRevision:0};
}

export class CashWorkspaceService {
 async get(context:AppContext,selectedId?:string) {
  return prisma.$transaction(async tx=>{
   let session=selectedId?await tx.cashSession.findFirst({where:{id:selectedId,companyId:context.company.id,userId:context.user.id,workspaceVersion:3}}):
    await tx.cashSession.findFirst({where:{companyId:context.company.id,userId:context.user.id,workspaceVersion:3},orderBy:[{status:'desc'},{createdAt:'desc'}]});
   if(session){
    await tx.$queryRaw`SELECT "id" FROM "CashSession" WHERE "id"=${session.id} AND "companyId"=${context.company.id} FOR SHARE`;
    session=await tx.cashSession.findUnique({where:{id:session.id}});
   }
   const dto=session?await this.serialize(tx,session,false):null;
   return {version:3,session:dto?{...dto,currentDeviceJoined:dto.participants.some(p=>p.deviceId===context.device.id)}:null,legacySessionsPresent:await tx.cashSession.count({where:{companyId:context.company.id,userId:context.user.id,workspaceVersion:{not:3}}})>0};
  });
 }
 async open(context:AppContext,raw:unknown) {
  permission(context,'cash.open');const input=workspaceOpenSchema.parse(raw);
  if (!validateCashV2Count(input,input.openingBalanceCents)) deny('Total da contagem de abertura invalido.','CASH_WORKSPACE_INVALID_COUNT',422);
  let id='';let joinedExisting=false;
  await prisma.$transaction(async tx=>{
   await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtext(${context.company.id}),hashtext(${context.user.id}))::text`;
   await device(tx,context);
   const replay=await tx.cashSession.findFirst({where:{companyId:context.company.id,userId:context.user.id,workspaceVersion:3,payload:{path:['workspaceOpenRequestId'],equals:input.requestId}}});
   if (replay) {
    if (asRecord(replay.payload).workspaceOpenFingerprint!==JSON.stringify(input)) deny('requestId de abertura reutilizado com outro conteudo.','CASH_REQUEST_CONFLICT',409);
    id=replay.id;joinedExisting=true;return;
   }
   let session=await tx.cashSession.findFirst({where:{companyId:context.company.id,userId:context.user.id,workspaceVersion:3,status:'open'}});
   if (session) {joinedExisting=true;session=await lockCashWorkspaceSession(tx,session.id,context.company.id);}
   if (!session) {
    const company=await tx.company.findUniqueOrThrow({where:{id:context.company.id}});
    const openingDetails={version:2,countedAmountCents:input.openingBalanceCents,...(input.denominations?{denominations:input.denominations}:{}),...(input.coinsCents===undefined?{}:{coinsCents:input.coinsCents}),blindClosureEnabled:company.cashBlindClosureEnabled,policyRevision:company.cashPolicyRevision};
    session=await tx.cashSession.create({data:{companyId:context.company.id,userId:context.user.id,deviceId:context.device.id,localUuid:randomUUID(),status:'open',openedAt:new Date(),openingBalanceCents:input.openingBalanceCents,workspaceVersion:3,payload:{cashWorkspaceVersion:3,cashMetadataVersion:3,openingDetails,awaitingInitialFloatConfirmation:false,workspaceOpenRequestId:input.requestId,workspaceOpenFingerprint:JSON.stringify(input)}}});
   }
   await attach(tx,session,context);id=session.id;
  });
  return {...await this.get(context,id),joinedExisting};
 }
 async join(context:AppContext,uuid:string,raw:unknown) {
  permission(context,'cash.open');workspaceJoinSchema.parse(raw);let id='';
  await prisma.$transaction(async tx=>{const session=await ownSession(tx,context,uuid,false);if(session.status!=='open')deny('Caixa ja concluido.','CASH_WORKSPACE_CLOSED',409);await attach(tx,session,context);id=session.id;});
  return this.get(context,id);
 }
 async requestClosure(context:AppContext,uuid:string,raw:unknown,reconfirmRequestId?:string) {
  permission(context,'cash.close');const input=workspaceCloseSchema.parse(raw);let id='';
  if (!validateCashV2Count(input,input.countedBalanceCents)) deny('Total da contagem invalido.','CASH_WORKSPACE_INVALID_COUNT',422);
  await prisma.$transaction(async tx=>{
   const session=await ownSession(tx,context,uuid);id=session.id;
   const replay=await tx.cashClosureRequest.findUnique({where:{companyId_requestId:{companyId:context.company.id,requestId:input.requestId}}});
   if (replay) {
    if(replay.sessionId!==session.id||replay.userId!==context.user.id||replay.requestFingerprint!==JSON.stringify(input))deny('requestId de contagem reutilizado.','CASH_REQUEST_CONFLICT',409);
    return;
   }
   if(session.status!=='open')deny('Caixa ja concluido.','CASH_WORKSPACE_CLOSED',409);
   if(input.expectedRevision>session.workspaceRevision)deny('Caixa mudou. Sincronize e confira novamente.','CASH_WORKSPACE_REVISION_CONFLICT',409);
   const current=await tx.cashClosureRequest.findFirst({where:{sessionId:session.id,status:{in:activeStates}},orderBy:{generation:'desc'}});
   if(current && (!reconfirmRequestId || current.requestId!==reconfirmRequestId))deny('Existe conferencia pendente.','CASH_CLOSURE_ALREADY_PENDING',409);
   if(reconfirmRequestId && !current)deny('Conferencia anterior nao esta pendente.','CASH_CLOSURE_NOT_PENDING',409);
   const expected=await cashWorkspaceExpected(tx,session);const policy=originalPolicy(session);
   if(!policy.blindClosureEnabled && typeof input.localExpectedBalanceCents!=='number')deny('Saldo local obrigatorio no modo normal.','CASH_LOCAL_EXPECTED_REQUIRED',422);
   const needsReview=input.expectedRevision!==session.workspaceRevision||(!policy.blindClosureEnabled&&input.localExpectedBalanceCents!==expected);
   if((policy.blindClosureEnabled||(!needsReview&&input.countedBalanceCents!==expected))&&!input.reason?.trim())deny('Motivo de contagem obrigatorio.','CASH_CLOSURE_REASON_REQUIRED',422);
   const generation=session.workspaceClosureGeneration+1;
   if(current)await tx.cashClosureRequest.update({where:{id:current.id},data:{status:'SUPERSEDED'}});
   await tx.cashClosureRequest.create({data:{companyId:context.company.id,sessionId:session.id,userId:context.user.id,requestId:input.requestId,generation,ledgerRevision:session.workspaceRevision,status:needsReview?'REVIEW_REQUIRED':'PENDING_SYNC',countedBalanceCents:input.countedBalanceCents,localExpectedBalanceCents:input.localExpectedBalanceCents??null,expectedBalanceCents:expected,differenceCents:input.countedBalanceCents-expected,reason:input.reason,notes:input.notes,originalCount:input,requestFingerprint:JSON.stringify(input)}});
   await tx.cashSession.update({where:{id:session.id},data:{workspaceClosureGeneration:generation}});
  });
  return this.get(context,id);
 }
 async acknowledge(context:AppContext,uuid:string,requestId:string,raw:unknown) {
  permission(context,'cash.close');const input=workspaceAckSchema.parse(raw);let id='';
  await prisma.$transaction(async tx=>{
   const session=await ownSession(tx,context,uuid);id=session.id;
   const closure=await tx.cashClosureRequest.findUnique({where:{companyId_requestId:{companyId:context.company.id,requestId}}});
   if(!closure||closure.sessionId!==session.id)deny('Conferencia nao encontrada.','CASH_CLOSURE_NOT_FOUND',404);
   if(closure.status==='CLOSED'&&session.status==='closed')return;
   if(closure.status==='SUPERSEDED'||closure.generation!==input.generation||closure.ledgerRevision!==input.revision||session.workspaceRevision!==input.revision)deny('Geracao da conferencia mudou. Atualize antes de confirmar sync.','CASH_CLOSURE_GENERATION_CONFLICT',409);
   if(closure.status==='REVIEW_REQUIRED')deny('Saldo mudou. Nova conferencia obrigatoria.','CASH_CLOSURE_REVIEW_REQUIRED',409);
   if(session.status!=='open')deny('Caixa ja concluido.','CASH_WORKSPACE_CLOSED',409);
   const unresolved=await tx.syncEvent.count({where:{companyId:context.company.id,userId:context.user.id,deviceId:context.device.id,status:{in:['PENDING','FAILED','CONFLICT']}}});
   if(unresolved)deny('Aparelho possui eventos pendentes ou em conflito.','CASH_DEVICE_NOT_DRAINED',409);
   const expected=await cashWorkspaceExpected(tx,session);
   if(expected!==closure.expectedBalanceCents){await invalidateCashWorkspaceClosure(tx,session,false);return;}
   await tx.cashClosureAck.upsert({where:{closureId_deviceId_generation:{closureId:closure.id,deviceId:context.device.id,generation:closure.generation}},create:{closureId:closure.id,deviceId:context.device.id,generation:closure.generation,ledgerRevision:closure.ledgerRevision},update:{}});
   await tx.cashWorkspaceParticipant.update({where:{sessionId_deviceId:{sessionId:session.id,deviceId:context.device.id}},data:{lastAckGeneration:closure.generation}});
   const participants=await tx.cashWorkspaceParticipant.findMany({where:{sessionId:session.id}});
   const acks=await tx.cashClosureAck.findMany({where:{closureId:closure.id,generation:closure.generation,ledgerRevision:closure.ledgerRevision}});
   if(!participants.every(p=>acks.some(a=>a.deviceId===p.deviceId)))return;
   // This lock is also acquired by every V3 operational write, preventing a final-ack/write race.
   const policy=originalPolicy(session);const original=asRecord(closure.originalCount);
   const closingDetails={version:2,sessionUuid:session.localUuid,expectedBalanceCents:expected,countedBalanceCents:closure.countedBalanceCents,differenceCents:closure.countedBalanceCents-expected,...policy,...(closure.reason?{reason:closure.reason}:{}),...(closure.notes?{notes:closure.notes}:{}),...(Array.isArray(original.denominations)?{denominations:original.denominations}:{}),...(typeof original.coinsCents==='number'?{coinsCents:original.coinsCents}:{})};
   await tx.cashSession.update({where:{id:session.id},data:{status:'closed',closedAt:new Date(),expectedBalanceCents:expected,closingBalanceCents:closure.countedBalanceCents,payload:{...asRecord(session.payload),closingDetails,closureRequestId:closure.requestId,closureGeneration:closure.generation}}});
   await tx.cashClosureRequest.update({where:{id:closure.id},data:{status:'CLOSED'}});
  });
  return this.get(context,id);
 }
 async ownerWorkspace(context:AppContext) {
  if(!['OWNER','ADMIN'].includes(context.membership.role)||!hasEmployeePermission(context.membership.permissions,'reports.advanced'))deny('Sem permissao para relatorios de caixa.');
  return prisma.$transaction(async tx=>{
  // Select the current/latest register in SQL rather than loading every historical shift.
  const selectedIds=await tx.$queryRaw<Array<{id:string}>>`SELECT DISTINCT ON ("userId") "id" FROM "CashSession" WHERE "companyId"=${context.company.id} AND "workspaceVersion"=3 ORDER BY "userId", CASE WHEN "status"='open' THEN 0 ELSE 1 END, "createdAt" DESC, "id" DESC`;
  const sessions=await tx.cashSession.findMany({where:{companyId:context.company.id,id:{in:selectedIds.map(row=>row.id)}},include:{user:{select:{id:true,name:true}},participants:{include:{device:{select:{deviceLabel:true}}},orderBy:{joinedAt:'asc'}},closureRequests:{where:{status:{not:'SUPERSEDED'}},orderBy:{generation:'desc'},take:1}}});
  const movements=await tx.cashEvent.findMany({where:{companyId:context.company.id,cashSessionId:{in:sessions.filter(s=>s.status==='open').map(s=>s.id)}}});
  const employees=sessions.map(selected=>{
   const expected=selected.status==='closed'?selected.expectedBalanceCents:cashWorkspaceLedgerExpected(selected.openingBalanceCents,movements.filter(event=>event.cashSessionId===selected.id));
   const dto=this.dto(selected,selected.participants,selected.closureRequests[0]??null,expected,true);
   return {employee:{id:selected.userId,name:selected.user?.name??'Funcionario'},activeSessionId:selected.status==='open'?selected.id:null,sessionUuid:selected.localUuid,sessionIds:[selected.id],status:dto.status,expectedBalanceCents:dto.expectedBalanceCents,countedBalanceCents:dto.closureRequest?.countedBalanceCents??null,differenceCents:dto.closureRequest?.differenceCents??null,participants:dto.participants,pendingReasons:dto.status==='REVIEW_REQUIRED'?['BALANCE_CHANGED_RECONFIRM_REQUIRED']:dto.status==='PENDING_SYNC'?['AWAITING_PARTICIPANT_SYNC']:[],revision:dto.revision,closureRequest:dto.closureRequest,canReview:selected.status==='closed'&&canReviewCash(context)};
  });
  const legacySessions=await tx.cashSession.count({where:{companyId:context.company.id,workspaceVersion:{not:3}}});
  return {version:3,summary:{openEmployees:employees.filter(e=>e.status!=='CLOSED').length,pendingEmployees:employees.filter(e=>['PENDING_SYNC','REVIEW_REQUIRED'].includes(e.status)).length,totalExpectedBalanceCents:employees.filter(e=>e.status!=='CLOSED').reduce((sum,e)=>sum+(e.expectedBalanceCents??0),0),confirmedCountedBalanceCents:employees.filter(e=>e.status==='CLOSED').reduce((sum,e)=>sum+(e.countedBalanceCents??0),0),legacySessions,expectedScope:'ACTIVE_EMPLOYEE_REGISTERS',confirmedCountedScope:'LATEST_CLOSED_PER_EMPLOYEE_WITHOUT_ACTIVE_REGISTER'},employees,legacySessionsPresent:legacySessions>0};
  },{isolationLevel:'RepeatableRead'});
 }
 private async serialize(tx:Tx,session:CashSession,manager:boolean) {
  const participants=await tx.cashWorkspaceParticipant.findMany({where:{sessionId:session.id},include:{device:{select:{deviceLabel:true}}},orderBy:{joinedAt:'asc'}});
  const closure=await tx.cashClosureRequest.findFirst({where:{sessionId:session.id,status:{not:'SUPERSEDED'}},orderBy:{generation:'desc'}});
  const movements=await tx.cashEvent.findMany({where:{companyId:session.companyId,cashSessionId:session.id}});
  const expected=session.status==='closed'?session.expectedBalanceCents:cashWorkspaceLedgerExpected(session.openingBalanceCents,movements);
  return {...this.dto(session,participants,closure,expected,manager),confirmedMovementUuids:movements.map(movement=>movement.localUuid)};
 }
 private dto(session:CashSession,participants:Array<{deviceId:string;lastAckGeneration:number|null;device:{deviceLabel:string|null}}>,closure:{requestId:string;generation:number;ledgerRevision:number;status:string;countedBalanceCents:number;expectedBalanceCents:number;differenceCents:number;reason:string|null}|null,expected:number|null,manager:boolean) {
  const policy=originalPolicy(session);const visible=manager||!policy.blindClosureEnabled||session.status==='closed';
  return {closingDetails:session.status==='closed'?(asRecord(session.payload).closingDetails??null):null,uuid:session.localUuid,id:session.id,openedAt:session.openedAt?.toISOString()??null,closedAt:session.closedAt?.toISOString()??null,employeeId:session.userId,status:session.status==='closed'?'CLOSED':closure?.status??'OPEN',revision:session.workspaceRevision,openingBalanceCents:session.openingBalanceCents,expectedBalanceCents:visible?expected:null,...policy,participants:participants.map(p=>({deviceId:p.deviceId,name:p.device.deviceLabel,lastAckGeneration:p.lastAckGeneration})),closureRequest:closure?{requestId:closure.requestId,generation:closure.generation,revision:closure.ledgerRevision,status:closure.status,countedBalanceCents:closure.countedBalanceCents,expectedBalanceCents:visible?closure.expectedBalanceCents:null,differenceCents:visible?closure.differenceCents:null,reason:closure.reason}:null};
 }
}
