const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../assets/school-viewport.js'), 'utf8');
const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
(async () => {
  for (const exists of [true, false]) {
    let meta = exists ? {name:'viewport',content:'width=device-width, minimum-scale=1, maximum-scale=1, user-scalable=no'} : null;
    let layoutFrames = 0;
    const document = {
      querySelector(selector) {
        assert.equal(selector, 'meta[name="viewport"]');
        return meta;
      },
      createElement(tag) { assert.equal(tag,'meta'); return {}; },
      head:{appendChild(node) { assert.equal(meta,null); meta=node; }},
      documentElement:{scrollWidth:1600}, body:{scrollWidth:1280},
      get cookie() { throw new Error('Credential access is forbidden'); },
      get forms() { throw new Error('Form access is forbidden'); },
    };
    const result = await new AsyncFunction('document','window','requestAnimationFrame',source)(
      document, {visualViewport:{width:1280},innerWidth:392},
      callback => { layoutFrames++; callback(); },
    );
    assert.deepEqual(JSON.parse(result),{viewport:1280,content:1600});
    assert.equal(layoutFrames,2);
    assert.equal(meta.name,'viewport');
    assert.match(meta.content,/minimum-scale=0.1/);
    assert.match(meta.content,/user-scalable=yes/);
  }
  console.log('School viewport checks passed (locked/missing viewport, layout frames, bounded geometry only).');
})().catch(error => { console.error(error); process.exitCode=1; });
