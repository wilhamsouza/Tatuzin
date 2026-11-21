import type { CashSession } from '@prisma/client';
import type { SyncMaterializerInput, SyncMaterializerResult } from '../sync/materializers/materializer.types';
import { asRecord, firstString, domainIdentityFor } from '../sync/materializers/payload-utils';
import { invalidateCashWorkspaceClosure, lockCashWorkspaceSession } from './cash-workspace.service';

type Guard = {session:CashSession|null;result:SyncMaterializerResult|null};
export async function guardCashWorkspaceWrite(input:SyncMaterializerInput):Promise<Guard> {
 const {tx,context,payload,event}=input;
 const uuid=firstString(payload,['cashSessionUuid','cashSessionLocalId','sessionUuid']);
 const id=firstString(payload,['cashSessionId','cashSessionServerId']);
 let session:CashSession|null=null;
 if(event.entity==='cashSession'){
  const ownUuid=firstString(payload,['uuid','localUuid'])??event.entityLocalId;
  if(ownUuid)session=await tx.cashSession.findFirst({where:{companyId:context.company.id,localUuid:ownUuid}});
 } else if(uuid||id)session=await tx.cashSession.findFirst({where:{companyId:context.company.id,OR:[...(uuid?[{localUuid:uuid}]:[]),...(id?[{id}]:[])]}});
 if(!session){
  const saleUuid=firstString(payload,['saleUuid','saleLocalId']);const saleId=firstString(payload,['saleId','saleServerId']);
  if(saleUuid||saleId){const sale=await tx.sale.findFirst({where:{companyId:context.company.id,OR:[...(saleUuid?[{localUuid:saleUuid}]:[]),...(saleId?[{id:saleId}]:[])]}});if(sale?.cashSessionId)session=await tx.cashSession.findFirst({where:{id:sale.cashSessionId,companyId:context.company.id}});}
 }
 if(!session){
  const orderUuid=firstString(payload,['operationalOrderUuid','orderUuid']);const orderId=firstString(payload,['operationalOrderId','orderId']);
  if(orderUuid||orderId){const order=await tx.operationalOrder.findFirst({where:{companyId:context.company.id,OR:[...(orderUuid?[{localUuid:orderUuid}]:[]),...(orderId?[{id:orderId}]:[])]}});if(order?.cashSessionId)session=await tx.cashSession.findFirst({where:{id:order.cashSessionId,companyId:context.company.id}});}
 }
 const rejected=(code:string,message:string):Guard=>({session,result:{outcome:'rejected',code,message}});
 if(session?.workspaceVersion!==3){
  if(payload.cashWorkspaceVersion===3)return rejected('CASH_WORKSPACE_NOT_FOUND','Caixa V3 deve existir na nuvem antes da primeira operacao offline.');
  return {session:null,result:null};
 }
 session=await lockCashWorkspaceSession(tx,session.id,context.company.id);
 if(!session)return rejected('CASH_WORKSPACE_NOT_FOUND','Caixa nao encontrado.');
 if(session.userId!==context.user.id)return rejected('CASH_WORKSPACE_ACTOR_MISMATCH','Voce nao pode operar caixa de outro funcionario.');
 const participant=await tx.cashWorkspaceParticipant.findUnique({where:{sessionId_deviceId:{sessionId:session.id,deviceId:context.device.id}}});
 if(!participant||participant.companyId!==context.company.id||participant.userId!==context.user.id)return rejected('CASH_PARTICIPATION_REQUIRED','Conecte este aparelho online antes de usar o caixa offline.');
 if(event.entity==='cashSession'){
  const status=firstString(payload,['status','state']);
  if(status&&['closed','fechado','CLOSED'].includes(status))return rejected('CASH_WORKSPACE_CLOSURE_COORDINATOR_REQUIRED','Fechamento V3 exige conferencia coordenada de todos os aparelhos.');
  return {session,result:{outcome:'duplicate',entityServerId:session.id}};
 }
 if(session.status==='closed'){
  // Exact existing immutable domain records may replay after final closure.
  const fields=event.entity==='cashMovement'?['localMovementUuid','movementUuid','uuid','localUuid','localId','id']:['uuid','localUuid','saleUuid','paymentUuid','paymentLocalId','receiptUuid','receiptLocalId','localId','id'];
  const localUuid=domainIdentityFor(event,payload,fields,{preferIdempotencyKey:true});
  if(localUuid){
   const where={companyId_localUuid:{companyId:context.company.id,localUuid}};
   const existing=event.entity==='cashMovement'?await tx.cashEvent.findUnique({where}):event.entity==='sale'?await tx.sale.findUnique({where}):['payment','receipt'].includes(event.entity)?await tx.financialEvent.findUnique({where}):null;
   if(existing)return {session,result:{outcome:'duplicate',entityServerId:existing.id}};
  }
  return rejected('CASH_WORKSPACE_CLOSED','Caixa V3 concluido; novos movimentos exigem novo caixa.');
 }
 return {session,result:null};
}
export async function recordCashWorkspaceWrite(input:SyncMaterializerInput,session:CashSession,result:SyncMaterializerResult) {
 if(result.outcome==='accepted')await invalidateCashWorkspaceClosure(input.tx,session,true);
}
