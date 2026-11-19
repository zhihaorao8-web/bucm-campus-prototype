const job = __LIBRARY_SEAT_COMMAND__;
const settings = __LIBRARY_SEAT_CONFIG__;
const result = (status, extra = {}) => JSON.stringify({
  status,
  bookingId: extra.bookingId ?? '',
  message: extra.message ?? '',
  reason: extra.reason ?? '',
});
const id = value => (typeof value === 'string' || Number.isSafeInteger(value)) &&
  /^(?:[1-9]\d{0,17})$/.test(String(value)) ? String(value) : '';
const day = value => typeof value === 'string' &&
  /^\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/.test(value);
const clock = value => {
  if (typeof value !== 'string') return '';
  const match = /^((?:[01]\d|2[0-3]):[0-5]\d)$/.exec(value.trim());
  return match ? match[1] : '';
};
const sanitize = (value, ...secrets) => {
  if (typeof value !== 'string') return '';
  let out = value.replace(/<[^>]*>/g, '').replace(/[\u0000-\u001f\u007f]/g, ' ');
  for (const secret of secrets) {
    if (secret && secret.length >= 2 && !/^\d{1,3}$/.test(secret)) {
      out = out.split(String(secret)).join('');
    }
  }
  return out.replace(/\s+/g, ' ').trim().slice(0, 160);
};
const readJson = async response => {
  if (!response.ok || !(response.headers.get('content-type') ?? '').includes('json')) {
    return null;
  }
  if (!response.body || typeof response.body.getReader !== 'function') {
    const raw = await response.text();
    if (raw.length > settings.maxBodyBytes) return null;
    try {
      return JSON.parse(raw);
    } catch (_) {
      return null;
    }
  }
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let size = 0, text = '';
  for (;;) {
    const {done, value} = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > settings.maxBodyBytes) {
      await reader.cancel();
      return null;
    }
    text += decoder.decode(value, {stream: true});
  }
  try {
    return JSON.parse(text + decoder.decode());
  } catch (_) {
    return null;
  }
};
const parseConfig = data => {
  if (Array.isArray(data)) {
    const map = {};
    for (const entry of data) {
      if (entry && typeof entry.sysKey === 'string') {
        map[entry.sysKey] = entry.sysValue;
      }
    }
    return map;
  }
  if (data && typeof data === 'object') return data;
  return null;
};

if (location.origin !== settings.origin || location.pathname !== settings.document ||
    window !== window.top) return result('precheck_error');
if (!job || job.action !== 'reserve') return result('precheck_error');
const seat = id(job.seat);
const start = clock(job.start);
const end = clock(job.end);
if (!seat || !Number.isSafeInteger(Number(seat)) || !day(job.date) ||
    !start || !end || start >= end) {
  return result('precheck_error');
}

const stop = new AbortController();
const timer = setTimeout(() => stop.abort(), settings.timeout);
let posted = false;
try {
  const configResp = await fetch(new URL('/ic-web/sysConfig/public', settings.origin), {
    method: 'GET',
    credentials: 'same-origin',
    cache: 'no-store',
    redirect: 'manual',
    signal: stop.signal,
  });
  const configBody = await readJson(configResp);
  const config = configBody && configBody.code === 0 ? parseConfig(configBody.data) : null;
  if (!config) return result('precheck_error');

  const resvCode = String(config.resvCode ?? '').trim();
  if (resvCode === '1' || resvCode === '2') {
    return result('web_required', {reason: 'captcha'});
  }
  const needToKnow = typeof config.needToKnow === 'string' ? config.needToKnow.trim() : '';
  if (needToKnow && needToKnow.split('-').some(part => part.split(',')[0].trim() === '8')) {
    return result('web_required', {reason: 'notice'});
  }
  const themeMust = Number(config.resvthememust ?? 0);
  if (Number.isFinite(themeMust) && (themeMust & 8) !== 0) {
    return result('web_required', {reason: 'theme'});
  }
  const memoRequired = Number(config.classKindMemoRequired ?? 0);
  if (Number.isFinite(memoRequired) && (memoRequired & 8) !== 0) {
    return result('web_required', {reason: 'memo'});
  }

  const userResp = await fetch(new URL('/ic-web/auth/userInfo', settings.origin), {
    method: 'GET',
    credentials: 'same-origin',
    cache: 'no-store',
    redirect: 'manual',
    signal: stop.signal,
  });
  if (userResp.type === 'opaqueredirect' || userResp.status === 401 || userResp.status === 403) {
    return result('login');
  }
  const userBody = await readJson(userResp);
  if (!userBody) return result('precheck_error');
  if (userBody.code === 300) return result('login');
  if (userBody.code !== 0) return result('precheck_error');
  const rawAcc = id(userBody.data?.accNo);
  if (!rawAcc) return result('precheck_error');
  const token = typeof userBody.data?.token === 'string' ? userBody.data.token.trim() : '';
  const secrets = [
    rawAcc,
    token,
    typeof userBody.data?.logonName === 'string' ? userBody.data.logonName.trim() : '',
    typeof userBody.data?.trueName === 'string' ? userBody.data.trueName.trim() : '',
    typeof userBody.data?.pid === 'string' ? userBody.data.pid.trim() : '',
  ];

  const headers = {
    'Content-Type': 'application/json;charset=UTF-8',
    'Accept': 'application/json',
    'lan': '1',
  };
  if (token) headers.token = token;
  const payload = {
    testName: '',
    appAccNo: rawAcc,
    memberKind: 1,
    resvDev: [Number(seat)],
    resvMember: [rawAcc],
    resvProperty: 0,
    sysKind: 8,
    resvBeginTime: `${job.date} ${start}:00`,
    resvEndTime: `${job.date} ${end}:00`,
    memo: '',
  };

  posted = true;
  const postResp = await fetch(new URL('/ic-web/reserve', settings.origin), {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
    credentials: 'same-origin',
    cache: 'no-store',
    redirect: 'manual',
    signal: stop.signal,
  });
  if (postResp.type === 'opaqueredirect' || postResp.status === 401 || postResp.status === 403) {
    return result('login');
  }
  if (!postResp.ok) return result('uncertain');
  const postBody = await readJson(postResp);
  if (!postBody) return result('uncertain');
  if (postBody.code === 300) return result('login');
  if (postBody.code === 0) {
    const bookingId = id(postBody.data?.resvId ?? postBody.data?.id ?? postBody.data);
    return result('ok', {
      bookingId,
      message: sanitize(postBody.message, ...secrets),
    });
  }
  if (Number.isSafeInteger(postBody.code)) {
    return result('rejected', {
      message: sanitize(postBody.message, ...secrets),
    });
  }
  return result('uncertain');
} catch (_) {
  return result(posted ? 'uncertain' : 'precheck_error');
} finally {
  clearTimeout(timer);
}
