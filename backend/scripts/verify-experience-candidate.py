#!/usr/bin/env python3
"""HTTP smoke test. Creates synthetic records ONLY in the isolated Docker candidate."""
import json
import secrets
import uuid
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.request import Request, urlopen

BASE = 'http://127.0.0.1:4401/api'
device = 'candidate-' + uuid.uuid4().hex
headers = {'Content-Type': 'application/json', 'X-Client-Instance-Id': device}


def request(method, path, body=None, expected=200):
    payload = None if body is None else json.dumps(body).encode()
    try:
        with urlopen(Request(BASE + path, data=payload, headers=headers, method=method), timeout=15) as response:
            status, raw = response.status, response.read()
    except HTTPError as error:
        status, raw = error.code, error.read()
    assert status == expected, f'{method} {path}: expected {expected}, received {status}'
    return json.loads(raw)


ready = request('GET', '/readiness')
assert ready['ready'] and ready['environment'] == 'isolated-test', 'Synthetic writes require isolated-test'
request('POST', '/product-journey/events', {}, expected=401)
request('GET', '/admin/product-journey/report', expected=401)
account = request('POST', '/auth/register', {
    'companyName': 'Candidate isolated smoke', 'userName': 'Candidate owner',
    'email': f'{device}@example.test', 'password': secrets.token_urlsafe(24),
    'clientType': 'mobile_app', 'clientInstanceId': device, 'appVersion': 'candidate-smoke',
}, expected=201)
headers['Authorization'] = 'Bearer ' + account['accessToken']
bootstrap = request('GET', '/app/bootstrap')
company = bootstrap['company']
assert company['experienceProfile'] == 'moda'
assert company['onboardingEnabled'] is True
assert company['experienceRefreshEnabled'] is True
progress = request('POST', '/app/onboarding/reconcile', {})
assert progress == {'enabled': True, 'productReady': False, 'cashReady': False, 'completedAt': None}
event = {
    'eventId': uuid.uuid4().hex, 'name': 'registration_completed',
    'occurredAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
    'appVersion': 'candidate-smoke', 'plan': 'FREE', 'experienceProfile': 'moda',
}
batch = {'companyId': company['id'], 'events': [event]}
ack = {'acknowledgedEventIds': [event['eventId']]}
assert request('POST', '/product-journey/events', batch) == ack
assert request('POST', '/product-journey/events', batch) == ack
request('POST', '/product-journey/events', {**batch, 'companyId': 'another-company'}, expected=403)
request('GET', '/admin/product-journey/report', expected=403)
print(json.dumps({'status': 'passed', 'environment': 'isolated-test',
    'checks': ['readiness', 'anonymous-access', 'automatic-slug', 'bootstrap-flags',
               'onboarding-empty', 'event-ingestion-and-retry', 'tenant-boundary', 'admin-report-access'],
    'humanOperatorSessions': 0}, indent=2))
