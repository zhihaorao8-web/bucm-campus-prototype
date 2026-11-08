(function(){
  // Invoked explicitly by the student on a school page. No passwords, cookies,
  // input values, tokens, or arbitrary page HTML are returned.
  var out={tables:[],blockedFrames:0};
  function walk(doc,depth){
    if(depth>3)return;
    Array.from(doc.querySelectorAll('table')).slice(0,60).forEach(function(table){
      if(table.querySelector('table') || table.closest('form') && table.querySelector('input[type=password]'))return;
      var rows=Array.from(table.rows).slice(0,100), grid=[], origins=[];
      rows.forEach(function(row,r){
        grid[r]=grid[r]||[]; var col=0;
        Array.from(row.cells).forEach(function(cell){
          while(grid[r][col])col++;
          var txt=(cell.innerText||'').trim().slice(0,6000), cs=Math.min(cell.colSpan||1,20),rs=Math.min(cell.rowSpan||1,40);
          var obj={text:txt,r:r,c:col,cs:cs,rs:rs};origins.push(obj);
          for(var y=r;y<r+rs;y++){grid[y]=grid[y]||[];for(var x=col;x<col+cs;x++)grid[y][x]=obj;}col+=cs;
        });
      });
      var headers={},headerRow=-1;
      origins.forEach(function(cell){
        var m=cell.text.match(/^(?:星期|周|礼拜)\s*([一二三四五六日天])(?:\s|$|\d|[（(])/);
        if(m){headers[cell.c]='一二三四五六日'.indexOf(m[1])+1;if(m[1]==='天')headers[cell.c]=7;headerRow=Math.max(headerRow,cell.r);}
      });
      if(Object.keys(headers).length<5)return;
      var candidates=[];
      origins.forEach(function(cell){
        if(cell.r<=headerRow||!headers[cell.c]||!cell.text||cell.cs>1)return;
        if(/^(?:无|暂无|[-—\s]+)$/.test(cell.text))return;
        var label=grid[cell.r]&&grid[cell.r][0]?grid[cell.r][0].text:'';
        // Shared cells may contain several courses; never merge them silently.
        var blocks=cell.text.split(/\n\s*\n+/).filter(function(t){return t.trim();});
        blocks.forEach(function(t){candidates.push({day:headers[cell.c],text:t,rowLabel:label});});
      });
      if(candidates.length)out.tables.push({candidates:candidates.slice(0,150)});
    });
    Array.from(doc.querySelectorAll('iframe,frame')).slice(0,15).forEach(function(f){try{walk(f.contentDocument,depth+1);}catch(e){out.blockedFrames++;}});
  }
  walk(document,0);return JSON.stringify(out);
})();
