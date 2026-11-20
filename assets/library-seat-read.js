const job = __LIBRARY_SEAT_COMMAND__;
const settings = __LIBRARY_SEAT_CONFIG__;
const result = (status, rows = [], count = 0) => JSON.stringify({status, rows, count});
const text = (value, max = 96) => typeof value === 'string' ? value.trim().slice(0, max) : '';
const id = value => (typeof value === 'string' || Number.isSafeInteger(value)) &&
  /^(?:[1-9]\d{0,17})$/.test(String(value)) ? String(value) : '';
const nonNegInt = value => {
  if (Number.isSafeInteger(value) && value >= 0 && value <= 9999999) return value;
  if (typeof value === 'string' && /^\d{1,7}$/.test(value.trim())) {
    const parsed = Number(value.trim());
    return Number.isSafeInteger(parsed) ? parsed : null;
  }
  return null;
};
const pad = n => String(n).padStart(2, '0');
const timestamp = value => {
  if (Number.isSafeInteger(value) && value >= 946684800000 && value <= 4102444800000) {
    const d = new Date(value + 8 * 3600 * 1000);
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())} ${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (/^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d+)?)?(?:Z|[+-](?:[01]\d|2[0-3]):?[0-5]\d)$/.test(trimmed)) {
      return timestamp(Date.parse(trimmed));
    }
    if (/^\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])[ T](?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d(?:\.\d+)?)?$/.test(trimmed)) {
      return trimmed.slice(0, 16).replace('T', ' ');
    }
  }
  return '';
};
const clock = value => {
  if (typeof value !== 'string') return '';
  const match = /^((?:[01]\d|2[0-3]):[0-5]\d)(?::[0-5]\d)?$/.exec(value.trim());
  return match ? match[1] : '';
};
const day = value => /^\d{4}-\d{2}-\d{2}$/.test(value);
const collectAreas = (nodes, floorName = '', depth = 0) => {
  const out = [];
  for (const node of nodes) {
    if (!node || typeof node !== 'object') return null;
    if (Number(node.property) === 1) continue;
    if (Array.isArray(node.children) && node.children.length > 0) {
      const nextFloor = text(node.name) || floorName;
      const nested = collectAreas(node.children, nextFloor, depth + 1);
      if (!nested) return null;
      out.push(...nested);
    } else if (Array.isArray(node.children) && depth === 0) {
      continue;
    } else {
      if (node.id === null || node.id === undefined || node.id === '') continue;
      const areaId = id(node.id);
      if (!areaId) continue;
      const areaName = text(node.name);
      if (!areaName) return null;
      out.push({id: areaId, name: areaName, floor: floorName});
    }
  }
  return out;
};
const isSeatOpen = (device, hours) => {
  if (hours.length === 0) return false;
  if (typeof device.openStart === 'string' && typeof device.openEnd === 'string' &&
      device.openStart && device.openStart === device.openEnd) return false;
  if (device.resvRule !== undefined &&
      (!device.resvRule || typeof device.resvRule !== 'object' ||
       Object.keys(device.resvRule).length === 0)) return false;
  if (typeof device.openState === 'number' && device.openState !== 1) return false;
  if (typeof device.devStatus === 'number' && device.devStatus !== 0) return false;
  return true;
};

if (location.origin !== settings.origin || location.pathname !== settings.document ||
    window !== window.top) return result('error');

let path, params;
switch (job.action) {
  case 'areas':
    path = '/ic-web/seatMenu';
    break;
  case 'seats':
    if (!id(job.area) || !day(job.date)) return result('error');
    path = '/ic-web/reserve';
    params = {roomIds: job.area, resvDates: job.date.replaceAll('-', ''), sysKind: '8'};
    break;
  case 'bookings':
    if (!day(job.begin) || !day(job.end) || !Number.isSafeInteger(job.page) ||
        job.page < 1) return result('error');
    path = '/ic-web/reserve/resvInfo';
    params = {beginDate: job.begin, endDate: job.end, page: job.page,
      pageNum: settings.bookingPageSize, needStatus: settings.bookingStatusFilter,
      orderKey: 'gmt_create', orderModel: 'desc'};
    break;
  default:
    return result('error');
}

const url = new URL(path, settings.origin);
if (params) url.search = new URLSearchParams(params);
const stop = new AbortController();
const timer = setTimeout(() => stop.abort(), settings.timeout);
try {
  const response = await fetch(url, {
    method: 'GET', credentials: 'same-origin', cache: 'no-store',
    redirect: 'manual', signal: stop.signal,
  });
  if (response.type === 'opaqueredirect' || response.status === 401 ||
      response.status === 403) return result('login');
  if (!response.ok || !(response.headers.get('content-type') ?? '').includes('json')) {
    return result('error');
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let size = 0, json = '';
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > settings.maxBodyBytes) {
      await reader.cancel();
      return result('error');
    }
    json += decoder.decode(value, {stream: true});
  }
  const body = JSON.parse(json + decoder.decode());
  if (body.code === 300) return result('login');
  const rawData = job.action === 'bookings' && body.data === null && body.count === 0
    ? []
    : body.data;
  if (body.code !== 0 || !Array.isArray(rawData) || rawData.length > settings.maxRows) {
    return result('error');
  }
  if (job.action === 'areas') {
    const rows = collectAreas(rawData);
    if (!rows || rows.length > settings.maxRows) return result('error');
    return result('ok', rows);
  }
  if (job.action === 'seats') {
    const visible = rawData
      .map((device, index) => ({device, index}))
      .filter(({device}) => device && ((Number(device.devProp) & 2) !== 0 || device.onlyView === true))
      .sort((a, b) => {
        const sa = Number(a.device.devSn), sb = Number(b.device.devSn);
        const fa = Number.isFinite(sa), fb = Number.isFinite(sb);
        if (fa && fb && sa !== sb) return sa - sb;
        if (fa !== fb) return fa ? -1 : 1;
        return a.index - b.index;
      })
      .map(({device}) => device);
    const rows = visible.map(device => {
      const hours = Array.isArray(device.openTimes) ? device.openTimes.slice(0, 32)
        .map(item => [clock(item?.openStartTime), clock(item?.openEndTime)]) : [];
      const reservations = Array.isArray(device.resvInfo) ? device.resvInfo
        .filter(item => item && (Number(item.resvStatus) & 128) === 0)
        .slice(0, 96)
        .map(item => [timestamp(item.startTime), timestamp(item.endTime)]) : [];
      const rule = device.resvRule && typeof device.resvRule === 'object' ? {
        minMinutes: nonNegInt(device.resvRule.minResvTime),
        maxMinutes: nonNegInt(device.resvRule.maxResvTime),
        earliestMinutes: nonNegInt(device.resvRule.earliestResvTime),
        latestMinutes: nonNegInt(device.resvRule.latestResvTime),
        cancelMinutes: nonNegInt(device.resvRule.cancelTime),
        limit: nonNegInt(device.resvRule.limit),
      } : null;
      return {
        id: id(device.devId), label: text(device.devName),
        viewOnly: device.onlyView === true,
        open: isSeatOpen(device, hours),
        hours,
        reservations,
        rule,
      };
    });
    if (rows.some(row => !row.id || !row.label ||
        row.hours.some(pair => !pair[0] || !pair[1]) ||
        row.reservations.some(pair => !pair[0] || !pair[1])) ||
      visible.some(device =>
        (Array.isArray(device.resvInfo) &&
         device.resvInfo.filter(item => item && (Number(item.resvStatus) & 128) === 0).length > 96) ||
        (Array.isArray(device.openTimes) && device.openTimes.length > 32))) {
      return result('error');
    }
    return result('ok', rows);
  }
  const rows = rawData.filter(row => row && Number(row.classKind) === 8).map(row => ({
    id: id(row.resvId),
    room: text(row.resvDevInfoList?.[0]?.roomName),
    seat: text(row.resvDevInfoList?.[0]?.devName),
    begin: timestamp(row.resvBeginTime), end: timestamp(row.resvEndTime),
    status: Number.isSafeInteger(row.resvStatus) ? row.resvStatus : null,
  }));
  if (!Number.isSafeInteger(body.count) || body.count < rawData.length ||
      rawData.length > settings.bookingPageSize ||
      rows.some(row => !row.id || !row.seat || !row.begin || !row.end)) return result('error');
  return result('ok', rows, body.count);
} catch (_) {
  return result('error');
} finally {
  clearTimeout(timer);
}
