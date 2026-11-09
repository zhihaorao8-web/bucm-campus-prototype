(function(){
  function allowed(url){try{var u=new URL(url);return u.protocol==='https:'&&!u.username&&!u.password&&(!u.port||u.port==='443')&&(u.hostname==='bucm.edu.cn'||u.hostname.endsWith('.bucm.edu.cn'));}catch(e){return false;}}
  function label(n){return (n.innerText||n.textContent||n.value||n.title||'').replace(/\s+/g,'').trim();}
  function matching(d,wanted){
    var nodes=Array.from(d.querySelectorAll('*')).filter(function(n){return !/^(SCRIPT|STYLE|TEXTAREA|SELECT|OPTION)$/.test(n.tagName)&&(n.tagName!=='INPUT'||/^(button|submit)$/i.test(n.type))&&label(n)===wanted&&n.getClientRects().length>0;});
    nodes=nodes.filter(function(n){return !nodes.some(function(other){return other!==n&&n.contains(other);});});
    var visible=nodes.filter(function(n){var r=n.getBoundingClientRect();return r.bottom>0&&r.top<d.defaultView.innerHeight&&r.right>0&&r.left<d.defaultView.innerWidth;});
    return visible.length?visible:nodes;
  }
  var docs=[];
  function walk(d,depth){if(!d||depth>3||!allowed(d.URL))return;docs.push(d);Array.from(d.querySelectorAll('iframe,frame')).forEach(function(f){try{walk(f.contentDocument,depth+1);}catch(e){}});}
  walk(document,0);
  function click(d,n){
    var link=n.closest('a');
    if(link&&link.getAttribute('href')&&!/^javascript:/i.test(link.getAttribute('href'))&&!allowed(new URL(link.getAttribute('href'),d.URL).href))return {state:'blocked'};
    if(n.form&&!allowed(new URL(n.form.getAttribute('action')||d.URL,d.URL).href))return {state:'blocked'};
    n.click();return {state:'navigating'};
  }
  for(var i=0;i<docs.length;i++){
    var d=docs[i];
    if(d.querySelector('input[type=password]'))return JSON.stringify({state:'login'});
    if((d.body.innerText||'').indexOf('学期理论课表')>=0){
      var selects=Array.from(d.querySelectorAll('select')),allFound=false;
      for(var j=0;j<selects.length;j++){
        var all=Array.from(selects[j].options).filter(function(o){return /^[(（]?全部[)）]?$/.test(label(o));});
        if(all.length===1){allFound=true;if(selects[j].value!==all[0].value){selects[j].value=all[0].value;selects[j].dispatchEvent(new Event('change',{bubbles:true}));return JSON.stringify({state:'navigating'});}}
      }
      if(!allFound)return JSON.stringify({state:'filterMissing'});
      var exports=matching(d,'导出');
      if(exports.length===1){
        var ids=[];selects.forEach(function(s){var o=s.options[s.selectedIndex];var t=String(s.value)+' '+(o?label(o):'');var m=t.match(/20\d{2}-20\d{2}-[12]/g)||[];ids=ids.concat(m);});
        if(!ids.length)ids=(d.body.innerText||'').match(/20\d{2}-20\d{2}-[12]/g)||[];
        ids=Array.from(new Set(ids));var result=click(d,exports[0]);if(result.state==='navigating'){result.state='exportClicked';if(ids.length===1)result.semester=ids[0];}return JSON.stringify(result);
      }
      if(exports.length>1)return JSON.stringify({state:'ambiguous'});
    }
  }
  for(var k=0;k<2;k++)for(var i=docs.length-1;i>=0;i--){
    var d=docs[i],wanted=['个人课表信息','本科教务系统'][k];
    var links=matching(d,wanted);
    if(links.length===1)return JSON.stringify(click(d,links[0]));
    if(links.length>1)return JSON.stringify({state:'ambiguous'});
  }
  return JSON.stringify({state:'waiting',documents:docs.length,resourceMatches:docs.reduce(function(n,d){return n+matching(d,'本科教务系统').length;},0)});
})();
