const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../assets/library-seat-write.js'), 'utf8');
const settings = {
  origin: 'https://school.example',
  document: '/config/config.js',
  bookingPageSize: 10,
  bookingStatusFilter: '8582',
  timeout: 120,
  maxRows: 40,
  maxBodyBytes: 32768,
};

async function runWrite(command, responder, origin = settings.origin, pathname = settings.document) {
  const body = source.replace('__LIBRARY_SEAT_COMMAND__', JSON.stringify(command))
    .replace('__LIBRARY_SEAT_CONFIG__', JSON.stringify(settings));
  const run = new Function('location', 'window', 'fetch', 'return (async () => {' + body + '})()');
  const window = {};
  window.top = window;
  const calls = [];
  const payload = await run({ origin, pathname }, window, async (url, options) => {
    calls.push({ url, options });
    return responder(url, options, calls.length);
  });
  return { data: JSON.parse(payload), calls };
}

function defaultConfig(overrides = {}) {
  const map = {
    resvCode: '0',
    needToKnow: '',
    resvthememust: null,
    classKindMemoRequired: '0',
    ...overrides,
  };
  return Response.json({
    code: 0,
    data: Object.entries(map).map(([sysKey, sysValue]) => ({ sysKey, sysValue })),
  });
}

function defaultUser(overrides = {}) {
  return Response.json({
    code: 0,
    data: {
      accNo: 987654321,
      token: 'synthetic-token',
      trueName: '合成用户',
      logonName: 'synthetic-logon',
      ...overrides,
    },
  });
}

test('rejects wrong origin, document, action, seat, date, or time before any fetch', async () => {
  const valid = { action: 'reserve', seat: '100', date: '2026-10-10', start: '09:00', end: '12:00' };
  const cases = [
    [valid, 'https://other.example', settings.document],
    [valid, settings.origin, '/index.html'],
    [{ ...valid, action: 'delete' }, settings.origin, settings.document],
    [{ ...valid, seat: 'abc' }, settings.origin, settings.document],
    [{ ...valid, date: '2026-13-01' }, settings.origin, settings.document],
    [{ ...valid, start: '12:00', end: '09:00' }, settings.origin, settings.document],
    [{ ...valid, start: '09:00', end: '09:00' }, settings.origin, settings.document],
  ];
  for (const [cmd, origin, doc] of cases) {
    const { data, calls } = await runWrite(cmd, () => Response.json({ code: 0 }), origin, doc);
    assert.equal(data.status, 'precheck_error');
    assert.equal(calls.length, 0);
  }
});

test('stops cleanly with web_required and zero POSTs when sysConfig requires web workflow', async () => {
  const valid = { action: 'reserve', seat: '100', date: '2026-10-10', start: '09:00', end: '12:00' };
  for (const [override, expectedReason] of [
    [{ resvCode: '1' }, 'captcha'],
    [{ resvCode: '2' }, 'captcha'],
    [{ needToKnow: '1,1-8,2' }, 'notice'],
    [{ resvthememust: '8' }, 'theme'],
    [{ classKindMemoRequired: '8' }, 'memo'],
  ]) {
    const { data, calls } = await runWrite(valid, url => {
      assert.equal(url.pathname, '/ic-web/sysConfig/public');
      return defaultConfig(override);
    });
    assert.equal(data.status, 'web_required');
    assert.equal(data.reason, expectedReason);
    assert.equal(calls.length, 1);
  }
});

test('returns precheck_error or login without POST when preflight fails', async () => {
  const valid = { action: 'reserve', seat: '100', date: '2026-10-10', start: '09:00', end: '12:00' };
  const cfgFail = await runWrite(valid, () => new Error('offline'));
  assert.equal(cfgFail.data.status, 'precheck_error');
  assert.equal(cfgFail.calls.length, 1);

  const userFail = await runWrite(valid, url => {
    if (url.pathname === '/ic-web/sysConfig/public') return defaultConfig();
    return Response.json({ code: 1, message: 'err' });
  });
  assert.equal(userFail.data.status, 'precheck_error');
  assert.equal(userFail.calls.length, 2);

  const needLogin = await runWrite(valid, url => {
    if (url.pathname === '/ic-web/sysConfig/public') return defaultConfig();
    return Response.json({ code: 300, message: '未登录' });
  });
  assert.equal(needLogin.data.status, 'login');
  assert.equal(needLogin.calls.length, 2);
});

test('submits single POST /ic-web/reserve with exact official fields and hides PII', async () => {
  const valid = { action: 'reserve', seat: '100', date: '2026-10-10', start: '09:00', end: '12:00' };
  const { data, calls } = await runWrite(valid, url => {
    if (url.pathname === '/ic-web/sysConfig/public') return defaultConfig();
    if (url.pathname === '/ic-web/auth/userInfo') return defaultUser();
    assert.equal(url.pathname, '/ic-web/reserve');
    return Response.json({ code: 0, message: '预约成功', data: { resvId: 5566 } });
  });
  assert.equal(calls.length, 3);
  const postCall = calls[2];
  assert.equal(postCall.options.method, 'POST');
  assert.equal(postCall.options.credentials, 'same-origin');
  assert.equal(postCall.options.redirect, 'manual');
  assert.equal(postCall.options.headers.lan, '1');
  assert.equal(postCall.options.headers.token, 'synthetic-token');
  assert.deepEqual(JSON.parse(postCall.options.body), {
    testName: '',
    appAccNo: '987654321',
    memberKind: 1,
    resvDev: [100],
    resvMember: ['987654321'],
    resvProperty: 0,
    sysKind: 8,
    resvBeginTime: '2026-10-10 09:00:00',
    resvEndTime: '2026-10-10 12:00:00',
    memo: '',
  });
  assert.deepEqual(data, { status: 'ok', bookingId: '5566', message: '预约成功', reason: '' });
  assert.doesNotMatch(JSON.stringify(data), /987654321|synthetic-token|合成用户|synthetic-logon/);
});

test('maps rejection, auth interruption, and network uncertainty without retrying POST', async () => {
  const valid = { action: 'reserve', seat: '100', date: '2026-10-10', start: '09:00', end: '12:00' };

  const rejected = await runWrite(valid, url => {
    if (url.pathname === '/ic-web/sysConfig/public') return defaultConfig();
    if (url.pathname === '/ic-web/auth/userInfo') return defaultUser();
    return Response.json({ code: 1, message: '<b>987654321</b> 合成用户 该时段已被占用' });
  });
  assert.equal(rejected.calls.length, 3);
  assert.equal(rejected.data.status, 'rejected');
  assert.equal(rejected.data.message, '该时段已被占用');

  const authInterrupted = await runWrite(valid, url => {
    if (url.pathname === '/ic-web/sysConfig/public') return defaultConfig();
    if (url.pathname === '/ic-web/auth/userInfo') return defaultUser();
    return Response.json({ code: 300, message: '登录超时' });
  });
  assert.equal(authInterrupted.calls.length, 3);
  assert.equal(authInterrupted.data.status, 'login');

  const http500 = await runWrite(valid, url => {
    if (url.pathname === '/ic-web/sysConfig/public') return defaultConfig();
    if (url.pathname === '/ic-web/auth/userInfo') return defaultUser();
    return new Response('server error', { status: 500 });
  });
  assert.equal(http500.calls.length, 3);
  assert.equal(http500.data.status, 'uncertain');

  const postTimeout = await runWrite(valid, url => {
    if (url.pathname === '/ic-web/sysConfig/public') return defaultConfig();
    if (url.pathname === '/ic-web/auth/userInfo') return defaultUser();
    throw new Error('network dropped after POST');
  });
  assert.equal(postTimeout.calls.length, 3);
  assert.equal(postTimeout.data.status, 'uncertain');
});
