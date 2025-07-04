import call from "./call";
import * as mika from "./mika";
import * as tray from "./tray";
import * as icon from "./icon";
import * as os from "./os";
import * as window_ from "./window";
import * as layer from "./layer";

function socket(path: string) {
    return new WebSocket(`ws://localhost:6797/${path}`);
}
const mikaShell = {
    tray,
    icon,
    os,
    window: window_,
    layer,
    mika,
    call,
    socket,
};
// @ts-ignore
window.mikaShell = mikaShell;
export default mikaShell;
