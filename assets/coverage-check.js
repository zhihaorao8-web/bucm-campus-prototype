(function (extract) {
  // Only extract from the school document whose rendered filters were checked.
  var matches = [], refreshing = false, blockedFrames = 0;
  function school(url) {
    try { var u = new URL(url); return u.protocol === 'https:' && !u.username && !u.password &&
      (!u.port || u.port === '443') && (u.hostname === 'bucm.edu.cn' || u.hostname.endsWith('.bucm.edu.cn')); }
    catch (e) { return false; }
  }
  function label(option) {
    return (option.innerText || option.textContent || '').replace(/\s/g, '');
  }
  function allWeeks(option) {
    return /^[(（]?全部[)）]?$/.test(label(option));
  }
  function renderedSelectionMatches(select) {
    var options = Array.from(select.options);
    var selected = options.filter(function (option) { return option.defaultSelected; }).pop();
    // A single-select with no explicit selection starts at its first enabled option.
    selected = selected || options.find(function (option) {
      return !option.disabled && !(option.parentElement && option.parentElement.disabled);
    });
    return !!selected && select.options[select.selectedIndex] === selected;
  }
  function walk(doc, depth) {
    if (!doc || depth > 3 || !school(doc.URL)) return;
    var weekControls = Array.from(doc.querySelectorAll('select')).filter(function (select) {
      var options = Array.from(select.options);
      return !select.multiple && options.some(allWeeks) && options.some(function (option) {
        return /^第?\d+周$/.test(label(option));
      });
    });
    if (weekControls.length === 1) {
      var week = weekControls[0], selectedWeek = week.options[week.selectedIndex];
      var text = doc.body ? doc.body.innerText || '' : '';
      if (selectedWeek && allWeeks(selectedWeek) && text.indexOf('学期理论课表') >= 0) {
        var otherFilters = week.form ? Array.from(week.form.querySelectorAll('select')).filter(function (select) {
          return select !== week;
        }) : [];
        // Selecting a new value updates the live control before the form response
        // replaces the old timetable. Compare with the current HTML's defaults.
        if (doc.readyState === 'complete' && renderedSelectionMatches(week) && otherFilters.every(renderedSelectionMatches)) {
          matches.push({document: doc, hasUnscheduled: /无课表课程|未排课课程/.test(text)});
        } else {
          refreshing = true;
        }
      }
    }
    Array.from(doc.querySelectorAll('iframe,frame')).slice(0,15).forEach(function (frame) {
      try { walk(frame.contentDocument, depth + 1); } catch (e) { blockedFrames++; }
    });
  }
  walk(document, 0);
  if (refreshing || matches.length !== 1) return JSON.stringify({full: false, refreshing: refreshing, blockedFrames: blockedFrames, tables: []});
  var match = matches[0], result = extract(match.document);
  result.full = true;
  result.hasUnscheduled = match.hasUnscheduled;
  result.blockedFrames = blockedFrames;
  return JSON.stringify(result);
})
