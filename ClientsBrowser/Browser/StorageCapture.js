// Injected at document end in every frame. Mirrors localStorage/sessionStorage to
// the app (for the backup string). Same-document writes don't fire `storage`
// events, so setItem/removeItem/clear are wrapped and a slow interval is kept.
(function () {
  if (window.__cbCapture) return;
  window.__cbCapture = true;
  var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.cb;
  if (!handler) return;

  function dump(storage) {
    var out = {};
    try {
      for (var i = 0; i < storage.length; i++) {
        var k = storage.key(i);
        out[k] = storage.getItem(k);
      }
    } catch (e) {}
    return out;
  }

  var timer = null;
  var lastSent = "";
  function send() {
    timer = null;
    try {
      var msg = { kind: "storage", origin: location.origin, local: dump(localStorage), session: dump(sessionStorage) };
      var text = JSON.stringify(msg);
      if (text === lastSent) return;
      lastSent = text;
      handler.postMessage(msg);
    } catch (e) {}
  }
  function schedule() {
    if (timer) return;
    timer = setTimeout(send, 500);
  }

  try {
    var proto = Object.getPrototypeOf(localStorage);
    ["setItem", "removeItem", "clear"].forEach(function (name) {
      var orig = proto[name];
      proto[name] = function () {
        var r = orig.apply(this, arguments);
        schedule();
        return r;
      };
    });
  } catch (e) {}

  window.addEventListener("storage", schedule);
  window.addEventListener("pagehide", send);
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "hidden") send();
  });
  setInterval(send, 30000);
  send();
})();
