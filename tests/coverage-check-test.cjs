const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(require('node:path').join(__dirname, '../assets/coverage-check.js'), 'utf8');
function filter(labels, selectedIndex, defaultIndex = -1) {
  return {selectedIndex, options: labels.map((textContent, index) => ({textContent, defaultSelected: index === defaultIndex}))};
}
function week(selectedIndex, defaultIndex) {
  return filter(['（全部）', '第10周'], selectedIndex, defaultIndex);
}
function doc(text, controls, {url = 'https://jw.bucm.edu.cn/schedule', frames = [], readyState = 'complete'} = {}) {
  return { URL: url, readyState, body: {innerText: text}, querySelectorAll(selector) {
    if (selector === 'select') return controls;
    if (selector === 'iframe,frame') return frames;
    throw Error('Unexpected DOM query: ' + selector);
  }};
}
function run(document) {
  const extracted = [];
  const extract = doc => { extracted.push(doc); return {tables: ['fixture']}; };
  const result = JSON.parse(vm.runInNewContext(`(${source})(extract)`, {document, URL, extract}));
  assert.equal(extracted.length, result.full ? 1 : 0);
  return {...result, extracted};
}
const title = '学期理论课表';
assert.equal(run(doc(title, [week(0)])).full, true);
assert.equal(run(doc(title, [week(0, 0)])).full, true);
assert.equal(run(doc(title, [week(1, 1)])).full, false);
assert.equal(run(doc('当前周课表', [week(0)])).full, false);
assert.equal(run(doc(title, [filter(['全部', '其他'], 0)])).full, false);
assert.equal(run(doc(title, [week(0)], {url: 'https://bucm.edu.cn.evil.example'})).full, false);

const staleWeek = run(doc(title, [week(0, 1)]));
assert.equal(staleWeek.refreshing, true);
assert.deepEqual(staleWeek.tables, []);
assert.equal(run(doc(title, [week(0)], {readyState: 'interactive'})).refreshing, true);
const allWeeks = week(0);
const pendingTerm = filter(['2026-2027-1', '2026-2027-2'], 1, 0);
allWeeks.form = {querySelectorAll: () => [allWeeks, pendingTerm]};
assert.equal(run(doc(title, [allWeeks, pendingTerm])).refreshing, true);
pendingTerm.options[0].defaultSelected = false;
pendingTerm.options[1].defaultSelected = true;
assert.equal(run(doc(title, [allWeeks, pendingTerm])).full, true);

const matched = doc(`${title} 无课表课程`, [week(0)]);
const staleFrame = {contentDocument: doc(title, [week(1, 1)])};
const currentFrame = {contentDocument: matched};
const scoped = run(doc('导航', [], {frames: [staleFrame, currentFrame]}));
assert.equal(scoped.hasUnscheduled, true);
assert.deepEqual(scoped.extracted, [matched]);
assert.equal(run(doc(title, [week(0)], {frames: [currentFrame]})).full, false);
const inaccessible = {get contentDocument() { throw Error('Cross origin'); }};
assert.equal(run(doc('导航', [], {frames: [inaccessible]})).blockedFrames, 1);
console.log('DOM coverage checks passed (rendered filters, pending navigation, exact source frame, footer and domain)');
