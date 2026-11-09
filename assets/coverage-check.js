(function () {
  // Inspect only timetable coverage controls, never authentication inputs.
  var full = false, unscheduled = false;
  function school(url) {
    try { var u = new URL(url); return u.protocol === 'https:' && !u.username && !u.password &&
      (!u.port || u.port === '443') && (u.hostname === 'bucm.edu.cn' || u.hostname.endsWith('.bucm.edu.cn')); }
    catch (e) { return false; }
  }
  function walk(doc, depth) {
    if (!doc || depth > 3 || !school(doc.URL)) return;
    var text = doc.body ? doc.body.innerText || '' : '';
    if (/无课表课程|未排课课程/.test(text)) unscheduled = true;
    if (text.indexOf('学期理论课表') >= 0) {
      Array.from(doc.querySelectorAll('select')).forEach(function (s) {
        var option = s.options && s.options[s.selectedIndex];
        var label = option ? (option.innerText || option.textContent || '').replace(/\s/g, '') : '';
        if (/^[(（]?全部[)）]?$/.test(label)) full = true;
      });
    }
    Array.from(doc.querySelectorAll('iframe,frame')).forEach(function (frame) {
      try { walk(frame.contentDocument, depth + 1); } catch (e) {}
    });
  }
  walk(document, 0);
  return JSON.stringify({full: full, hasUnscheduled: unscheduled});
})();
