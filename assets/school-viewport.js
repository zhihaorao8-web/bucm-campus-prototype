// Display-only adaptation for the school's fixed-width PC page. No form or
// authentication storage access. This body is run with callAsyncJavaScript.
var viewport = document.querySelector('meta[name="viewport"]');
if (!viewport && document.head) {
  viewport = document.createElement('meta');
  viewport.name = 'viewport';
  document.head.appendChild(viewport);
}
if (viewport) {
  viewport.content = 'width=1280, initial-scale=0.25, minimum-scale=0.1, maximum-scale=5, user-scalable=yes';
}
// Wait for viewport changes to reach layout before computing the fit ratio.
await new Promise(function(resolve) {
  requestAnimationFrame(function() { requestAnimationFrame(resolve); });
});
return JSON.stringify({
  viewport: window.visualViewport ? window.visualViewport.width : window.innerWidth,
  content: Math.max(document.documentElement.scrollWidth, document.body ? document.body.scrollWidth : 0)
});
