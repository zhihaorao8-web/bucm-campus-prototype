const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(path.join(__dirname, '../assets/library-seat-read.js'), 'utf8');
const settings = {
  origin: 'https://school.example',
  document: '/config/config.js',
  bookingPageSize: 10,
  bookingStatusFilter: '8582',
  timeout: 100,
  maxRows: 40,
  maxBodyBytes: 32768,
};

async function read(command, response, origin = settings.origin) {
  const body = source.replace('__LIBRARY_SEAT_COMMAND__', JSON.stringify(command))
    .replace('__LIBRARY_SEAT_CONFIG__', JSON.stringify(settings));
  const run = new Function('location', 'window', 'fetch', 'return (async () => {' + body + '})()');
  const window = {};
  window.top = window;
  const calls = [];
  const payload = await run({ origin, pathname: settings.document }, window, async (url, options) => {
    calls.push({ url, options });
    if (response instanceof Error) throw response;
    return Response.json(response);
  });
  return { data: JSON.parse(payload), calls };
}

test('seat query uses the official visible bit, sorts by devSn, drops finished entries, and strips PII', async () => {
  const prototype = {
    devName: '合成座位',
    devProp: 2,
    openState: 1,
    devStatus: 0,
    openStart: '08:30',
    openEnd: '22:00',
    resvRule: {
      minResvTime: 30,
      maxResvTime: 240,
      earliestResvTime: 1440,
      latestResvTime: 0,
      cancelTime: 30,
      limit: 8,
    },
    openTimes: [{ openStartTime: '08:30:00', openEndTime: '22:00:00' }],
    resvInfo: [
      { startTime: '2026-10-10 12:30:00', endTime: '2026-10-10 13:30:00', resvStatus: 4, trueName: '合成姓名' },
      { startTime: '2026-10-10 09:00:00', endTime: '2026-10-10 10:00:00', resvStatus: 128, logonName: '合成学号' },
    ],
  };
  const epochStart = Date.UTC(2026, 9, 10, 6, 0, 0); // 14:00 Beijing time
  const epochEnd = Date.UTC(2026, 9, 10, 7, 30, 0); // 15:30 Beijing time
  const { data, calls } = await read({ action: 'seats', area: '14', date: '2026-10-10' }, {
    code: 0,
    data: [
      { ...prototype, devId: 100, devSn: 20, devName: 'B02' },
      { ...prototype, devId: 101, devSn: 5, devProp: 0, devName: 'HIDDEN' },
      { ...prototype, devId: 102, devSn: 30, devProp: 0, onlyView: true, devName: 'V03' },
      {
        ...prototype,
        devId: 103,
        devSn: 10,
        devName: 'A01',
        resvInfo: [{ startTime: epochStart, endTime: epochEnd, resvStatus: 2, accNo: '9999' }],
      },
    ],
  });
  assert.equal(calls[0].url.pathname, '/ic-web/reserve');
  assert.equal(calls[0].url.search, '?roomIds=14&resvDates=20261010&sysKind=8');
  assert.equal(calls[0].options.method, 'GET');
  assert.equal(calls[0].options.credentials, 'same-origin');
  assert.equal(calls[0].options.redirect, 'manual');
  assert.deepEqual(data.rows.map(row => row.id), ['103', '100', '102']);
  assert.equal(data.rows[2].viewOnly, true);
  assert.deepEqual(data.rows[0].hours, [['08:30', '22:00']]);
  assert.deepEqual(data.rows[0].rule, {
    minMinutes: 30,
    maxMinutes: 240,
    earliestMinutes: 1440,
    latestMinutes: 0,
    cancelMinutes: 30,
    limit: 8,
  });
  assert.deepEqual(data.rows[0].reservations, [['2026-10-10 14:00', '2026-10-10 15:30']]);
  assert.deepEqual(data.rows[1].reservations, [['2026-10-10 12:30', '2026-10-10 13:30']]);
  assert.doesNotMatch(JSON.stringify(data), /trueName|合成姓名|devProp|logonName|合成学号|accNo/);
});

test('seat query evaluates open/closed rules and rejects malformed clocks or timestamps', async () => {
  const base = {
    devId: 10,
    devName: 'A10',
    devProp: 2,
    openTimes: [{ openStartTime: '08:30', openEndTime: '22:00' }],
    resvInfo: [],
  };
  const closedBySameWindow = await read({ action: 'seats', area: '14', date: '2026-10-10' }, {
    code: 0,
    data: [{ ...base, openStart: '08:30', openEnd: '08:30', resvRule: { minResvTime: 30 } }],
  });
  assert.equal(closedBySameWindow.data.rows[0].open, false);

  const closedByEmptyRule = await read({ action: 'seats', area: '14', date: '2026-10-10' }, {
    code: 0,
    data: [{ ...base, resvRule: {} }],
  });
  assert.equal(closedByEmptyRule.data.rows[0].open, false);

  const closedByOpenState = await read({ action: 'seats', area: '14', date: '2026-10-10' }, {
    code: 0,
    data: [{ ...base, openState: 0, resvRule: { minResvTime: 30 } }],
  });
  assert.equal(closedByOpenState.data.rows[0].open, false);

  const openWithoutOpenState = await read({ action: 'seats', area: '14', date: '2026-10-10' }, {
    code: 0,
    data: [{ ...base, resvRule: { minResvTime: 30 } }],
  });
  assert.equal(openWithoutOpenState.data.rows[0].open, true);

  const badClock = await read({ action: 'seats', area: '14', date: '2026-10-10' }, {
    code: 0,
    data: [{ ...base, openTimes: [{ openStartTime: '99:99', openEndTime: '22:00' }] }],
  });
  assert.equal(badClock.data.status, 'error');

  const badReservation = await read({ action: 'seats', area: '14', date: '2026-10-10' }, {
    code: 0,
    data: [{ ...base, resvInfo: [{ startTime: 'not-a-date', endTime: '2026-10-10 10:00:00' }] }],
  });
  assert.equal(badReservation.data.status, 'error');
});

test('areas flattens nested floors and skips non-numeric pseudo nodes and enter-lib nodes', async () => {
  const { data } = await read({ action: 'areas' }, {
    code: 0,
    data: [
      { id: 'abc999', name: '快速抢座' },
      { id: 'comseat', name: '常用座位' },
      { id: 99, name: '入馆预约', property: 1 },
      { id: 1, name: '一层', children: [] },
      {
        id: 2,
        name: '二层',
        children: [
          { id: 32, name: '二层北区' },
          { id: 33, name: '子区', children: [{ id: 34, name: '静音区' }] },
        ],
      },
    ],
  });
  assert.equal(data.status, 'ok');
  assert.deepEqual(data.rows, [
    { id: '32', name: '二层北区', floor: '二层' },
    { id: '34', name: '静音区', floor: '子区' },
  ]);
});

test('bookings accept null empty data and stay scoped to seat records while keeping pagination count', async () => {
  const emptyNull = await read(
    { action: 'bookings', begin: '2026-10-05', end: '2026-10-11', page: 1 },
    { code: 0, count: 0, data: null },
  );
  assert.deepEqual(emptyNull.data, { status: 'ok', rows: [], count: 0 });

  const { data, calls } = await read(
    { action: 'bookings', begin: '2026-10-05', end: '2026-10-11', page: 2 },
    {
      code: 0, count: 12,
      data: [
        { classKind: 2 },
        {
          classKind: 8, resvId: 13, resvStatus: 4,
          resvBeginTime: '2026-10-10 12:30:00', resvEndTime: '2026-10-10 13:30:00',
          resvDevInfoList: [{ devName: '合成座位', roomName: '合成区域' }],
          account: '合成账户',
          appAccNo: '10086',
        },
      ],
    },
  );
  assert.equal(calls[0].url.pathname, '/ic-web/reserve/resvInfo');
  assert.equal(calls[0].url.searchParams.get('needStatus'), '8582');
  assert.equal(calls[0].url.searchParams.get('page'), '2');
  assert.equal(data.count, 12);
  assert.deepEqual(data.rows.map(row => row.id), ['13']);
  assert.doesNotMatch(JSON.stringify(data), /合成账户|10086|resvDevInfoList/);
});

test('booking timestamps with explicit offsets display in school time across midnight', async () => {
  const { data } = await read(
    { action: 'bookings', begin: '2027-06-07', end: '2027-06-13', page: 1 },
    {
      code: 0, count: 1,
      data: [{
        classKind: 8, resvId: 14, resvStatus: 2,
        resvBeginTime: '2027-06-08T23:30:00.000Z',
        resvEndTime: '2027-06-09T02:00:00.000+02:00',
        resvDevInfoList: [{ devName: '合成座位', roomName: '合成区域' }],
      }],
    },
  );
  assert.deepEqual(data, {
    status: 'ok', count: 1, rows: [{
      id: '14', room: '合成区域', seat: '合成座位', status: 2,
      begin: '2027-06-09 07:30', end: '2027-06-09 08:00',
    }],
  });
});

test('authentication failure differs from an empty list and a network error', async () => {
  const job = { action: 'areas' };
  assert.equal((await read(job, { code: 300, data: null })).data.status, 'login');
  assert.deepEqual((await read(job, { code: 0, data: [] })).data, { status: 'ok', rows: [], count: 0 });
  assert.equal((await read(job, new Error('synthetic timeout'))).data.status, 'error');
});

test('the bridge rejects other document origins, URLs and commands before fetch', async () => {
  assert.equal((await read({ action: 'areas' }, {}, 'https://other.example')).calls.length, 0);
  assert.equal((await read({ action: 'seats', area: '../wrong', date: '2026-10-10' }, {})).calls.length, 0);
  assert.equal((await read({ action: 'cancel', id: '42' }, {})).calls.length, 0);
});

test('seat coordinates normalize valid percentages and nullify malformed values without failing', async () => {
  const base = {
    devName: '坐标测试',
    devProp: 2,
    openState: 1,
    devStatus: 0,
    resvRule: { minResvTime: 30 },
    openTimes: [{ openStartTime: '08:30:00', openEndTime: '22:00:00' }],
    resvInfo: [],
  };
  const { data } = await read({ action: 'seats', area: '32', date: '2026-10-10' }, {
    code: 0,
    data: [
      { ...base, devId: 1, devSn: 1, devName: 'A1', coordinate: '12.5,64.2' },
      { ...base, devId: 2, devSn: 2, devName: 'A2', coordinate: ' 0 , 100 ' },
      { ...base, devId: 3, devSn: 3, devName: 'A3', coordinate: null },
      { ...base, devId: 4, devSn: 4, devName: 'A4', coordinate: '' },
      { ...base, devId: 5, devSn: 5, devName: 'A5', coordinate: '-1,50' },
      { ...base, devId: 6, devSn: 6, devName: 'A6', coordinate: '101,20' },
      { ...base, devId: 7, devSn: 7, devName: 'A7', coordinate: 'abc,10' },
      { ...base, devId: 8, devSn: 8, devName: 'A8', coordinate: '10,20,30' },
    ],
  });
  assert.equal(data.status, 'ok');
  assert.deepEqual(data.rows.map(r => [r.id, r.x, r.y]), [
    ['1', 12.5, 64.2],
    ['2', 0, 100],
    ['3', null, null],
    ['4', null, null],
    ['5', null, null],
    ['6', null, null],
    ['7', null, null],
    ['8', null, null],
  ]);
});
