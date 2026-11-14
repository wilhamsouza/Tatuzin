#!/usr/bin/env python3
"""Verify the actual mobile sync contract only on the isolated candidate."""
import json
import runpy
import uuid
from datetime import datetime, timezone
from pathlib import Path

# The shared smoke refuses all writes unless readiness says isolated-test.
state = runpy.run_path(str(Path(__file__).with_name('verify-experience-candidate.py')))
def request(method, path, body=None, expected=200):
    return state['request'](method, path, body, expected=202 if path == '/sync/push' else expected)

first_uuid, second_uuid, sale_uuid = (str(uuid.uuid4()) for _ in range(3))
first = request('POST', '/customers', {'localUuid': first_uuid, 'name': 'Candidate client A'}, expected=201)['customer']
second = request('POST', '/customers', {'localUuid': second_uuid, 'name': 'Candidate client B'}, expected=201)['customer']


def event(entity, payload, identity=None):
    return {'eventId': str(uuid.uuid4()), 'feature': 'pdv', 'entity': entity,
            'operation': 'create' if entity == 'sale' else 'append',
            'entityLocalId': identity or str(uuid.uuid4()),
            'occurredAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
            'payload': payload}


created = request('POST', '/sync/push', {'events': [event('sale', {
    'uuid': sale_uuid, 'customerServerId': first['id'], 'customerUuid': first_uuid,
    'saleType': 'vista', 'paymentMethod': 'pix', 'totalCents': 2500,
    'creditUsedCents': 0, 'creditGeneratedCents': 0,
}, sale_uuid)]})
assert len(created['accepted']) == 1, created
sale_id = created['accepted'][0]['entityServerId']
original = request('GET', '/sales/' + sale_id)['sale']
assert original['customerId'] == first['id']
assignment = event('saleCustomerAssignment', {
    'saleUuid': sale_uuid, 'customerServerId': second['id'], 'customerUuid': second_uuid,
    'previousCustomerServerId': first['id'], 'previousCustomerUuid': first_uuid,
    'expectedRevision': 0,
})
assigned = request('POST', '/sync/push', {'events': [assignment]})
assert len(assigned['accepted']) == 1, assigned
retry = request('POST', '/sync/push', {'events': [assignment]})
assert len(retry['duplicates']) == 1, retry
updated = request('GET', '/sales/' + sale_id)['sale']
assert updated['customerId'] == second['id']
for field in ['totalAmountCents', 'totalCostCents', 'paymentType', 'paymentMethod', 'status']:
    assert updated[field] == original[field], field
pulled = request('GET', '/sync/pull?sinceVersion=0&includeOwnEvents=true')
changes = pulled.get('changes', pulled.get('events', []))
projected = [change for change in changes if change['entity'] == 'saleCustomerAssignment']
assert projected and projected[-1]['projection']['customerServerId'] == second['id'], pulled
assert projected[-1]['projection']['revision'] == 1
stale = event('saleCustomerAssignment', assignment['payload'])
conflict = request('POST', '/sync/push', {'events': [stale]})
assert len(conflict['conflicts']) == 1, conflict
lock = request('POST', '/sync/push', {'events': [event('saleCustomerLock', {'saleUuid': sale_uuid})]})
assert len(lock['accepted']) == 1, lock
blocked = request('POST', '/sync/push', {'events': [event('saleCustomerAssignment', {
    **assignment['payload'], 'customerServerId': first['id'], 'customerUuid': first_uuid,
    'previousCustomerServerId': second['id'], 'previousCustomerUuid': second_uuid, 'expectedRevision': 1,
})]})
assert len(blocked['rejected']) == 1, blocked
assert request('GET', '/sales/' + sale_id)['sale']['customerId'] == second['id']
print(json.dumps({'status': 'passed', 'environment': 'isolated-test', 'checks': [
    'customer-before-sale', 'assignment-via-sync', 'retry-deduplication',
    'cross-device-projection', 'stale-revision-conflict', 'return-lock', 'money-unchanged',
]}, indent=2))
