import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CashSessionMaterializer } from './cash-session.materializer';
import { cashMetadataEqual, closingDetailsSchema, openingDetailsSchema, validateCashV2Count } from './cash-session-v2';
import type { SyncMaterializerInput } from './materializer.types';
const opening = {version:2,countedAmountCents:1000,denominations:[{valueCents:1000,quantity:1}],blindClosureEnabled:true,policyRevision:0};
const closing = {version:2,sessionUuid:'session-1',expectedBalanceCents:1100,countedBalanceCents:1000,differenceCents:-100,reason:'Contagem fisica',blindClosureEnabled:true,policyRevision:0};
function fixture(payload: Record<string,unknown>, existing: Record<string,unknown>|null = null) {
  const writes:unknown[]=[];
  const tx = { $queryRaw:async()=>[], cashSession:{findUnique:async()=>existing,findFirst:async()=>null,create:async({data}:any)=>{writes.push(data);return {id:'server-1',updatedAt:new Date()};},update:async({data}:any)=>{writes.push(data);return {id:'server-1',updatedAt:new Date()};}} };
  const input = {tx,context:{company:{id:'company'},device:{id:'device'},user:{id:'user'},membership:{role:'OWNER',permissions:['*']}},event:{operation:'upsert',entity:'cashSession',entityLocalId:'session-1',occurredAt:new Date().toISOString()},payload:{uuid:'session-1',openedAt:new Date().toISOString(),...payload}} as unknown as SyncMaterializerInput;
  return {input,writes};
}
const stored = {id:'server-1',userId:'user',deviceId:'device',status:'closed',payload:{openingDetails:opening,closingDetails:closing},openedAt:new Date(),lastLocalSequence:null};
test('V2 schemas reject fractional cents and mismatched count',()=>{
 assert.equal(openingDetailsSchema.safeParse({...opening,countedAmountCents:0.5}).success,false);
 assert.equal(closingDetailsSchema.safeParse({...closing,expectedBalanceCents:0.1}).success,false);
 assert.equal(validateCashV2Count(opening,1000),true);
 assert.equal(validateCashV2Count(opening,1001),false);
 assert.equal(validateCashV2Count({denominations:[{valueCents:500,quantity:1},{valueCents:500,quantity:1}]},1000),false);
 assert.equal(cashMetadataEqual({a:1,b:2},{b:2,a:1}),true);
});
test('V2 opening records exact count and policy snapshot',async()=>{
 const f=fixture({status:'open',openingDetails:opening});
 assert.equal((await new CashSessionMaterializer().materialize(f.input)).outcome,'accepted');
 assert.equal((f.writes[0] as any).openingBalanceCents,1000);
 assert.deepEqual((f.writes[0] as any).payload.openingDetails,opening);
});
test('blind closure requires reason even at zero difference',async()=>{
 const f=fixture({status:'closed',openingDetails:opening,closingDetails:{...closing,expectedBalanceCents:1000,differenceCents:0,reason:''}});
 assert.equal((await new CashSessionMaterializer().materialize(f.input)).outcome,'rejected');assert.equal(f.writes.length,0);
});
test('closing expected/count/difference must agree',async()=>{
 for(const patch of [{differenceCents:1},{expectedBalanceCents:1001},{countedBalanceCents:1001}]) {
 const f=fixture({status:'closed',openingDetails:opening,closingDetails:{...closing,...patch}});
 assert.equal((await new CashSessionMaterializer().materialize(f.input)).outcome,'rejected'); }
});
test('identical closure replay makes no writes and changed closure conflicts',async()=>{
 const f=fixture({status:'closed',closingDetails:closing},stored);
 assert.equal((await new CashSessionMaterializer().materialize(f.input)).outcome,'duplicate');assert.equal(f.writes.length,0);
 const changed=fixture({status:'closed',closingDetails:{...closing,reason:'Outro motivo'}},stored);
 const result=await new CashSessionMaterializer().materialize(changed.input);
 assert.equal(result.outcome,'conflict');assert.equal(changed.writes.length,0);
});
test('V2 cannot transfer devices or retrofit legacy opening',async()=>{
 for(const row of [{...stored,status:'open',deviceId:'other'},{...stored,status:'open',payload:{}}]) {
 const f=fixture({status:'open',openingDetails:opening},row);
 assert.equal((await new CashSessionMaterializer().materialize(f.input)).outcome,'conflict');assert.equal(f.writes.length,0); }
});
test('synchronized provisional auto-opening confirms count once, preserving policy and device',async()=>{
 const zeroOpening={...opening,countedAmountCents:0,denominations:[]};
 const provisional={...stored,status:'open',payload:{openingDetails:zeroOpening,awaitingInitialFloatConfirmation:true}};
 const confirmed=fixture({status:'open',openingDetails:opening,awaitingInitialFloatConfirmation:false},provisional);
 assert.equal((await new CashSessionMaterializer().materialize(confirmed.input)).outcome,'accepted');
 assert.equal((confirmed.writes[0] as any).openingBalanceCents,1000);
 assert.equal((confirmed.writes[0] as any).payload.awaitingInitialFloatConfirmation,false);
 const row={...provisional,payload:(confirmed.writes[0] as any).payload};
 const retry=fixture({status:'open',openingDetails:opening,awaitingInitialFloatConfirmation:false},row);
 assert.equal((await new CashSessionMaterializer().materialize(retry.input)).outcome,'accepted');
 for(const patch of [{openingDetails:{...opening,countedAmountCents:2000,denominations:[{valueCents:1000,quantity:2}]}},{awaitingInitialFloatConfirmation:true}]) {
  const changed=fixture({status:'open',openingDetails:opening,awaitingInitialFloatConfirmation:false,...patch},row);
  assert.equal((await new CashSessionMaterializer().materialize(changed.input)).outcome,'conflict');assert.equal(changed.writes.length,0);
 }
 for(const patch of [{openingDetails:{...opening,policyRevision:1}},{openingDetails:{...opening,blindClosureEnabled:false}}]) {
  const changed=fixture({status:'open',awaitingInitialFloatConfirmation:false,...patch},provisional);
  assert.equal((await new CashSessionMaterializer().materialize(changed.input)).outcome,'conflict');
 }
});
