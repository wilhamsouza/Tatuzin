import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { before, after, test } from 'node:test';
import type { AddressInfo } from 'node:net';
import type { Server } from 'node:http';
import jwt from 'jsonwebtoken';
import { createApp } from '../../app';
import { env } from '../../config/env';
import { prisma } from '../../database/prisma';

const target = new URL(process.env.DATABASE_URL ?? 'postgresql://invalid/invalid');
if (target.hostname !== '127.0.0.1' || target.port !== '55442' || target.pathname !== '/tatuzin_cash_test') {
  throw new Error('Cash HTTP test requires disposable DB 127.0.0.1:55442/tatuzin_cash_test');
}
const run = `cash-http-${randomUUID()}`;
let server: Server;
let base: string;
const companies: string[] = [];
const users: string[] = [];
type Actor = { userId: string; companyId: string; token: string; client: string };
async function actor(companyId?: string, role: 'OWNER' | 'CASHIER' | 'SELLER' = 'OWNER'): Promise<Actor> {
  if (!companyId) {
    const company = await prisma.company.create({data:{name:run,legalName:run,slug:`${run}-${companies.length}`}});
    companyId = company.id;
    companies.push(companyId);
    await prisma.license.create({data:{companyId,plan:'pro',status:'ACTIVE',startsAt:new Date(),maxDevices:10,syncEnabled:true}});
  }
  const user = await prisma.user.create({data:{email:`${run}-${users.length}@test.invalid`,name:`Funcionário ${users.length}`,passwordHash:'test-only'}});
  users.push(user.id);
  const membership = await prisma.membership.create({data:{companyId,userId:user.id,role:role === 'OWNER' ? 'OWNER' : 'OPERATOR',isDefault:true}});
  await prisma.employeeProfile.create({data:{companyId,userId:user.id,membershipId:membership.id,name:user.name,email:user.email,emailNormalized:user.email,role,status:'ACTIVE'}});
  const client = randomUUID();
  await prisma.companyDevice.create({data:{companyId,userId:user.id,clientInstanceId:client,deviceLabel:'Aparelho de teste',platform:'node-test',status:'ACTIVE'}});
  const token = jwt.sign({sub:user.id,companyId,membershipId:membership.id,membershipRole:membership.role,email:user.email,clientInstanceId:client,isPlatformAdmin:false},env.JWT_SECRET,{expiresIn:'15m'});
  return {userId:user.id,companyId,token,client};
}
async function anotherDevice(original: Actor): Promise<Actor> {
  const client = randomUUID();
  await prisma.companyDevice.create({data:{companyId:original.companyId,userId:original.userId,clientInstanceId:client,deviceLabel:'Segundo aparelho',platform:'node-test',status:'ACTIVE'}});
  const claims = jwt.decode(original.token) as Record<string, unknown>;
  delete claims.iat; delete claims.exp;
  const token = jwt.sign({...claims,clientInstanceId:client},env.JWT_SECRET,{expiresIn:'15m'});
  return {...original,token,client};
}
async function call(who: Actor, method: string, path: string, body?: Record<string,unknown>, status = 200): Promise<any> {
  const response = await fetch(`${base}${path}`,{method,headers:{Authorization:`Bearer ${who.token}`,'X-Client-Instance-Id':who.client,...(body?{'Content-Type':'application/json'}:{})},body:body?JSON.stringify(body):undefined});
  const result = await response.json() as any;
  assert.equal(response.status,status,`${method} ${path}: ${JSON.stringify(result)}`);
  return result;
}
async function movement(who: Actor, uuid: string, amount: number) {
  const movementUuid = randomUUID();
  const event = {eventId:randomUUID(),feature:'pdv',entity:'cashMovement',operation:'create',entityLocalId:movementUuid,occurredAt:new Date().toISOString(),payload:{uuid:movementUuid,cashWorkspaceVersion:3,cashEmployeeId:who.userId,cashSessionUuid:uuid,eventType:'venda',amountCents:amount,paymentMethod:'dinheiro'}};
  return call(who,'POST','/sync/push',{events:[event]},202);
}
before(async () => {
  server = createApp().listen(0);
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}/api`;
});
after(async () => {
  await new Promise<void>((resolve,reject) => server.close(error => error ? reject(error) : resolve()));
  await prisma.company.deleteMany({where:{id:{in:companies}}});
  await prisma.user.deleteMany({where:{id:{in:users}}});
  await prisma.$disconnect();
});

test('real HTTP two-device employee cash waits for every participant and requires review after late cash', async () => {
  const first = await actor();
  const second = await anotherDevice(first);
  const coworker = await actor(first.companyId,'CASHIER');
  const foreign = await actor();
  const seller = await actor(first.companyId,'SELLER');
  await call(seller,'POST','/app/cash/sessions/open',{requestId:randomUUID(),openingBalanceCents:0},403);
  const opened = await call(first,'POST','/app/cash/sessions/open',{requestId:randomUUID(),openingBalanceCents:5005,denominations:[{valueCents:5000,quantity:1}],coinsCents:5});
  const uuid = opened.session.uuid as string;
  const observed = await call(second,'GET','/app/cash/workspace');
  assert.equal(observed.session.uuid,uuid);
  assert.equal(observed.session.currentDeviceJoined,false);
  const joined = await call(second,'POST',`/app/cash/sessions/${uuid}/join`,{requestId:randomUUID()});
  assert.equal(joined.session.currentDeviceJoined,true);
  const recovered = await call(second,'POST','/app/cash/sessions/open',{requestId:randomUUID(),openingBalanceCents:9999});
  assert.equal(recovered.session.uuid,uuid);
  assert.equal(recovered.session.openingBalanceCents,5005);
  const other = await call(coworker,'POST','/app/cash/sessions/open',{requestId:randomUUID(),openingBalanceCents:7007});
  assert.notEqual(other.session.uuid,uuid);
  await call(coworker,'POST',`/app/cash/sessions/${uuid}/join`,{requestId:randomUUID()},403);
  await call(foreign,'POST',`/app/cash/sessions/${uuid}/join`,{requestId:randomUUID()},404);
  const receipt = await movement(first,uuid,101);
  assert.equal(receipt.accepted.length,1,JSON.stringify(receipt));
  const current = (await call(first,'GET','/app/cash/workspace')).session;
  assert.equal(current.expectedBalanceCents,5106);
  const requestId = randomUUID();
  const request = {requestId,expectedRevision:current.revision,countedBalanceCents:5106,localExpectedBalanceCents:5106,reason:'Conferência inicial'};
  const pending = (await call(first,'POST',`/app/cash/sessions/${uuid}/closure-requests`,request)).session;
  assert.equal(pending.status,'PENDING_SYNC');
  const oldAck = {generation:pending.closureRequest.generation,revision:pending.revision,drained:true};
  const oneAck = (await call(first,'POST',`/app/cash/sessions/${uuid}/closure-requests/${requestId}/ack`,oldAck)).session;
  assert.equal(oneAck.status,'PENDING_SYNC');
  assert.equal((await prisma.cashSession.findUniqueOrThrow({where:{id:oneAck.id}})).status,'open');
  assert.equal((await movement(second,uuid,202)).accepted.length,1);
  const changed = (await call(first,'GET','/app/cash/workspace')).session;
  assert.equal(changed.status,'REVIEW_REQUIRED');
  assert.equal(changed.expectedBalanceCents,5308);
  assert.equal(changed.closureRequest.countedBalanceCents,5106);
  await call(second,'POST',`/app/cash/sessions/${uuid}/closure-requests/${requestId}/ack`,oldAck,409);
  const revisedId = randomUUID();
  const revised = (await call(first,'POST',`/app/cash/sessions/${uuid}/closure-requests/${requestId}/reconfirm`,{requestId:revisedId,expectedRevision:changed.revision,countedBalanceCents:5308,localExpectedBalanceCents:5308,reason:'Nova conferência após venda do segundo aparelho',notes:'Conferência central vencedora',denominations:[{valueCents:100,quantity:53}],coinsCents:8})).session;
  assert.equal(revised.status,'PENDING_SYNC');
  const ack = {generation:revised.closureRequest.generation,revision:revised.revision,drained:true};
  await call(first,'POST',`/app/cash/sessions/${uuid}/closure-requests/${revisedId}/ack`,ack);
  const completed = (await call(second,'POST',`/app/cash/sessions/${uuid}/closure-requests/${revisedId}/ack`,ack)).session;
  assert.equal(completed.status,'CLOSED');
  assert.equal(completed.closureRequest.countedBalanceCents,5308);
  assert.equal(completed.closingDetails.notes,'Conferência central vencedora');
  assert.deepEqual(completed.closingDetails.denominations,[{valueCents:100,quantity:53}]);
  assert.equal(completed.closingDetails.coinsCents,8);
  assert.equal((await call(second,'POST',`/app/cash/sessions/${uuid}/closure-requests/${revisedId}/ack`,ack)).session.status,'CLOSED');
  const frozen = (await prisma.cashSession.findUniqueOrThrow({where:{id:completed.id}})).payload;
  const next = (await call(first,'POST','/app/cash/sessions/open',{requestId:randomUUID(),openingBalanceCents:1})).session;
  assert.notEqual(next.uuid,uuid);
  await call(first,'POST',`/app/cash/sessions/${uuid}/closure-requests/${revisedId}/ack`,ack);
  assert.equal((await prisma.cashSession.findUniqueOrThrow({where:{id:next.id}})).status,'open');
  assert.deepEqual((await prisma.cashSession.findUniqueOrThrow({where:{id:completed.id}})).payload,frozen);
  const overview = await call(first,'GET','/owner/reports/cash-workspace');
  assert.equal(overview.summary.openEmployees,2);
  assert.equal(overview.summary.totalExpectedBalanceCents,7008);
  assert.equal(overview.employees.find((row:any)=>row.employee.id===first.userId).sessionUuid,next.uuid);
});
