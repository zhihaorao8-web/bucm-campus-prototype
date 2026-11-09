const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(require('node:path').join(__dirname, '../assets/coverage-check.js'), 'utf8');
function doc(text, choice, url = 'https://jw.bucm.edu.cn/schedule', frames = []) {
  return { URL: url, body: {innerText: text}, querySelectorAll(selector) {
    if (selector === 'select') return choice === null ? [] : [{options: [{textContent: choice}], selectedIndex: 0}];
    if (selector === 'iframe,frame') return frames;
    throw Error('Unexpected DOM query: ' + selector);
  }};
}
function run(document) { return JSON.parse(vm.runInNewContext(source, {document, URL})); }
assert.equal(run(doc('学期理论课表', '全部')).full, true);
assert.equal(run(doc('学期理论课表', '第10周')).full, false);
assert.equal(run(doc('当前周课表', '全部')).full, false);
assert.equal(run(doc('学期理论课表', '全部', 'https://bucm.edu.cn.evil.example')).full, false);
assert.equal(run(doc('导航', null, undefined, [{contentDocument: doc('学期理论课表 无课表课程', '全部')}])).hasUnscheduled, true);
assert.equal(run(doc('导航', null, undefined, [{get contentDocument() { throw Error('Cross origin'); }}])).full, false);
console.log('DOM coverage controls checks passed (full semester, partial week, footer, domain and frames)');
