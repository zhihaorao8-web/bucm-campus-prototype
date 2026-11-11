(function () {
  'use strict';
  // Arguments are provided by the native UI; no credentials leave this page.
  var command = __CLASSROOM_COMMAND__;
  var vpnPrefix = '/https/77726476706e69737468656265737421e1ff5bd225256b5d300d8db9d6562d/';
  var trusted = location.protocol === 'https:' && !location.port &&
    (location.hostname === 'qhz.bucm.edu.cn' && location.pathname.indexOf('/coursePlatform/') === 0 ||
     location.hostname === 'webvpn.bucm.edu.cn' && location.pathname.indexOf(vpnPrefix + 'coursePlatform/') === 0);
  if (!trusted) return JSON.stringify({state: 'navigate'});
  if (command.action === 'playbackStatus') return JSON.stringify({state:'playback',videos:Array.from(document.querySelectorAll('video')).map(function(v){return {paused:v.paused,time:v.currentTime,frames:v.getVideoPlaybackQuality?v.getVideoPlaybackQuality().totalVideoFrames:0,width:v.videoWidth,height:v.videoHeight};})});
  var notice = Array.from(document.querySelectorAll('.el-message--error,.el-notification.error')).map(function (n) { return n.innerText || ''; }).join(' ');
  if (/登录|身份失效|会话|过期|unauthorized/i.test(notice)) return JSON.stringify({state: 'authentication'});
  if (/权限|无权|禁止|拒绝/.test(notice)) return JSON.stringify({state: 'forbidden'});
  if (/网络|超时|请求失败|服务器错误/.test(notice)) return JSON.stringify({state: 'error'});
  var root = document.querySelector('#app');
  var components = [], visited = 0;
  function walk(v, depth) {
    if (!v || depth > 20 || ++visited > 500) return;
    components.push(v);
    (v.$children || []).forEach(function (c) { walk(c, depth + 1); });
  }
  walk(root && root.__vue__, 0);
  var catalog = components.find(function (v) { return Array.isArray(v.courseList) && typeof v.seeCourseDetail === 'function'; });
  var videos = components.find(function (v) { return v.paramsData && Array.isArray(v.tableData) && typeof v.seeDetail === 'function' && typeof v.handleCurrentChange === 'function'; });
  function text(v) { return v == null ? '' : String(v).slice(0, 500); }
  function term(v) {
    var m = text(v).match(/^(20\d{2})-?(20\d{2})-?0?([12])$/);
    return m ? m[1] + '-' + m[2] + '-' + m[3] : '';
  }
  function course(v) { return {id: text(v.id), name: text(v.name), teacher: text(v.teacherName), code: text(v.course_num), group: text(v.className), semester: term(v.xq_code)}; }
  if (command.action === 'catalogRoute' && root && root.__vue__ && root.__vue__.$router) {
    root.__vue__.$router.push({path:'/courseCenter/index',query:{firstMenuId:'11'}});
    return JSON.stringify({state:'opening'});
  }
  if (command.action === 'returnRecords' && root && root.__vue__ && root.__vue__.$router) {
    Array.from(document.querySelectorAll('video')).forEach(function (v) { v.pause(); });
    root.__vue__.$router.replace('/courseCenter/courseVideo/videoListXS');
    return JSON.stringify({state:'opening'});
  }
  if (command.action === 'choose' && catalog) {
    var choices = catalog.courseList.filter(function (v) { return text(v.id) === command.id && term(v.xq_code) === command.semester; });
    if (choices.length !== 1) return JSON.stringify({state: 'missing'});
    // Same official context and route used by seeCourseDetail; stay in this
    // document instead of depending on an Android programmatic popup.
    sessionStorage.setItem('nowNav',11);
    choices[0].user_level = catalog.user_level;
    catalog.$store.commit('user/SET_COURSEINFO',choices[0]);
    catalog.$router.push('/courseCenter/courseVideo/videoListXS');
    return JSON.stringify({state: 'opening'});
  }
  if (command.action === 'recordsRoute') {
    var link = Array.from(document.querySelectorAll('a[href]')).find(function (a) { return a.getAttribute('href') === '#/courseCenter/courseVideo/videoListXS'; });
    if (link) { link.click(); return JSON.stringify({state: 'opening'}); }
  }
  if (command.action === 'page' && videos) {
    if (command.page < 1 || command.page > Math.ceil(videos.total / videos.pageSize)) return JSON.stringify({state: 'missing'});
    window.__campusClassroomPending = {ref: videos.tableData};
    videos.handleCurrentChange(command.page);
    return JSON.stringify({state: 'opening'});
  }
  if (command.action === 'play' && videos) {
    var rows = videos.tableData.filter(function (v) { return text(v.rpId) === command.id && String(v.shareType) === '1'; });
    if (rows.length !== 1) return JSON.stringify({state: 'missing'});
    var record = rows[0];
    videos.$router.push({path:'/videoDetailInNewWindowXS',query:{rpId:record.rpId,courseSchedId:record.courseSchedId||0,courseId:record.course_id,timeTableId:record.timeTableId,rpLookType:2,isResource:1}});
    return JSON.stringify({state: 'opening'});
  }
  if (catalog) {
    return JSON.stringify({state: 'catalog', semester: term(catalog.xqCode), courses: catalog.courseList.slice(0, 1000).map(course)});
  }
  if (videos) {
    if (window.__campusClassroomPending && window.__campusClassroomPending.ref === videos.tableData) return JSON.stringify({state: 'loading'});
    delete window.__campusClassroomPending;
    return JSON.stringify({state: 'records', course: course(videos.paramsData), page: Number(videos.page), pageSize: Number(videos.pageSize), total: Number(videos.total), records: videos.tableData.slice(0, 100).map(function (v) {
      return {id: text(v.rpId), label: text(v.rpName), date: text(v.date_time), place: text(v.roomName), published: String(v.shareType) === '1'};
    })});
  }
  return JSON.stringify({state: 'navigate'});
})();
