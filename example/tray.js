const tray = window.mikaShell.tray;
const arrayToUrl = (arr) => {
    const uint8Array = new Uint8Array(arr);
    const blob = new Blob([uint8Array], { type: "image/png" });
    const imageUrl = URL.createObjectURL(blob);
    return imageUrl;
};
var mounted = [];
function mount(divID) {
    if (mounted.includes(divID)) {
        return;
    }
    mounted.push(divID);
}
export default {
    mount,
};
function updataTray(divID, trayData) {
    const div = document.getElementById(divID);
    trayData.icon.pixmap.sort((a, b) => b.width * b.height - a.width * a.height);
    const imageUrl = arrayToUrl(trayData.icon.pixmap[0].webp);
    for (let i = 0; i < div.children.length; i++) {
        const img = div.children[i];
        if (img.dataset.service !== trayData.service) continue;
        URL.revokeObjectURL(img.src);
        img.src = imageUrl;
        return;
    }

    const img = document.createElement("img");
    img.src = imageUrl;
    img.className = "tray-icon";
    img.dataset["service"] = trayData.service;
    img.addEventListener("contextmenu", function (e) {
        e.preventDefault();
        tray.getMenu(trayData.service).then((menu) => {
            console.log("tray-menu", menu);
        });
    });
    img.onclick = () => tray.activate(trayData.service, 0, 0);
    div.appendChild(img);
}
const trayProxy = new Proxy(
    {},
    {
        get: (target, prop) => {
            return target[prop];
        },
        set: (target, prop, value) => {
            target[prop] = value;
            mounted.forEach((id) => updataTray(id, value));
            return true;
        },
        deleteProperty: (target, prop) => {
            delete target[prop];
            console.log("tray-removed", prop);
            mounted.forEach((div) => {
                const img = div.querySelector(`img[data-service="${prop}"]`);
                if (img) {
                    div.removeChild(img);
                }
            });
            return true;
        },
    }
);
tray.proxy(trayProxy);
