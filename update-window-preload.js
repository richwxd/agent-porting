// src/main/window/software-update/update-window-preload.ts
var import_electron = require("electron");
var STATE_CHANNEL = "software-update:state";
var GET_SNAPSHOT_CHANNEL = "software-update:getSnapshot";
var ACTION_CHANNEL = "software-update:action";
var CONTENT_HEIGHT_CHANNEL = "software-update:contentHeight";
var ALLOWED_ACTIONS = [
  "cancel",
  "retry",
  "restart",
  "close"
];
var handlers = [];
import_electron.ipcRenderer.on(STATE_CHANNEL, (_event, snapshot) => {
  for (const handler of handlers) {
    try {
      handler(snapshot);
    } catch {
    }
  }
});
import_electron.contextBridge.exposeInMainWorld("softwareUpdateAPI", {
  onState(handler) {
    handlers.push(handler);
    return () => {
      const index = handlers.indexOf(handler);
      if (index >= 0) {
        handlers.splice(index, 1);
      }
    };
  },
  getSnapshot() {
    return import_electron.ipcRenderer.invoke(GET_SNAPSHOT_CHANNEL).catch(() => null);
  },
  invoke(action) {
    if (!ALLOWED_ACTIONS.includes(action)) {
      return;
    }
    import_electron.ipcRenderer.send(ACTION_CHANNEL, action);
  },
  /** 上报实测内容高度，由主进程校正窗高；越界值在主进程侧丢弃。 */
  reportContentHeight(height) {
    if (typeof height !== "number" || !Number.isFinite(height)) {
      return;
    }
    import_electron.ipcRenderer.send(CONTENT_HEIGHT_CHANNEL, height);
  }
});
