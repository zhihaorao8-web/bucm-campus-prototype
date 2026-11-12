'use strict';
/* Experimental read-only adapter. Run inside an initialized official page.
 * The injected request function is the school's client, never a credential.
 * Android use is restricted to the opt-in direct-catalog experiment. */
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory;
  else root.createCampusRecordingApi = factory;
})(typeof window === 'object' ? window : this, function (request, location, timeoutMs = 10000) {
  const prefix = '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/';
  const trusted = () => location.protocol === 'https:' && !location.port &&
    !location.username && !location.password &&
    (location.hostname === 'qhz.bucm.edu.cn' && location.pathname.startsWith('/coursePlatform/') ||
      location.hostname === 'webvpn.bucm.edu.cn' && location.pathname.startsWith(prefix + 'coursePlatform/'));
  if (typeof request !== 'function' || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 30000) throw new Error('unsupported-client');
  let generation = 0, busy = false;
  const sources = new Map();
  function fail() { throw new Error('invalid-data'); }
  function text(v, required = false) {
    if (v == null && !required) return '';
    if (typeof v !== 'string' || v.length > 500 || required && !v.trim()) fail();
    return v;
  }
  function term(v) {
    const m = text(v, true).match(/^(20\d{2})-?(20\d{2})-?0?([12])$/);
    if (!m || Number(m[2]) !== Number(m[1]) + 1) fail();
    return m[1] + '-' + m[2] + '-' + m[3];
  }
  function course(c) {
    return {id: text(c.id, true), name: text(c.name, true), teacher: text(c.teacherName),
      code: text(c.course_num, true), group: text(c.className), semester: term(c.xq_code)};
  }
  async function execute(work) {
    if (!trusted()) return {state: 'untrusted'};
    if (busy) return {state: 'busy'};
    busy = true;
    const epoch = generation;
    let timer;
    const active = () => { if (epoch !== generation || !trusted()) throw new Error('cancelled'); };
    try {
      const result = await Promise.race([work(active), new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error('timeout')), timeoutMs);
      })]);
      active();
      return result;
    } catch (e) {
      const status = e?.response?.status;
      const state = epoch !== generation || !trusted() ? 'cancelled' :
        status === 401 ? 'authentication' : status === 403 ? 'forbidden' :
        e?.message === 'invalid-data' ? 'invalid-data' : e?.message === 'timeout' ? 'timeout' : 'error';
      return {state}; // No request config, URL, headers, body or error message escapes.
    } finally {
      clearTimeout(timer);
      if (epoch === generation) { busy = false; generation++; }
    }
  }
  return {
    cancel() { generation++; busy = false; sources.clear(); },
    catalog(xqCode, boy = '') {
      return execute(async active => {
        const semester = term(xqCode);
        if (!['', 1, 2].includes(boy)) fail();
        const rows = await request({url: '/cp/course/getCourseList', method: 'post', data: {xqCode, boy}, timeout: timeoutMs});
        active();
        if (!Array.isArray(rows) || rows.length > 1000) fail();
        const next = new Map();
        const courses = rows.map(row => {
          const item = course(row);
          if (item.semester !== semester || next.has(item.id)) fail();
          next.set(item.id, {item, fz: text(row.fz_id, true), rawTerm: text(row.xq_code, true)});
          return item;
        });
        active();
        sources.clear();
        next.forEach((value, key) => sources.set(key, value));
        return {state: 'catalog', semester, courses};
      });
    },
    records(id, page = 1) {
      return execute(async active => {
        const source = sources.get(id);
        if (!source || !Number.isSafeInteger(page) || page < 1 || page > 1000) fail();
        const d = await request({url: '/cp/courseInfo/ResourceList', method: 'post',
          data: {courseCode: source.item.code, fz_id: source.fz, beginTime: '', endTime: '',
            xqCode: source.rawTerm, page, pageSize: 10}, timeout: timeoutMs});
        active();
        if (!d || !Number.isSafeInteger(d.total) || d.total < 0 || d.total > 10000 ||
          !Array.isArray(d.list) || d.list.length > 10 || page > Math.max(1, Math.ceil(d.total / 10))) fail();
        const expected = Math.min(10, Math.max(0, d.total - (page - 1) * 10));
        if (d.list.length !== expected) fail();
        const seen = new Set();
        const records = d.list.map(r => {
          const rid = text(r.rpId, true), date = text(r.date_time, true);
          if (seen.has(rid) || !/^20\d{2}-\d{2}-\d{2}$/.test(date) ||
            Number.isNaN(Date.parse(date)) || new Date(date).toISOString().slice(0, 10) !== date ||
            !['1', '2'].includes(String(r.shareType))) fail();
          seen.add(rid);
          return {id: rid, label: text(r.rpName), date, place: text(r.roomName), published: String(r.shareType) === '1'};
        });
        return {state: 'records', course: source.item, page, pageSize: 10, total: d.total, records};
      });
    }
  };
});
