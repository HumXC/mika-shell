import call from "./call";
export * from "./layer-and-window";
export type Edge = "left" | "right" | "top" | "bottom";
export type Layers = "background" | "bottom" | "top" | "overlay";
export type KeyboardMode = "none" | "exclusive" | "ondemand";
const EdgeToNumber: Record<Edge, number> = {
    left: 0,
    right: 1,
    top: 2,
    bottom: 3,
};
const LayersToNumber = {
    background: 0,
    bottom: 1,
    top: 2,
    overlay: 3,
};
const KeyboardModeToNumber = {
    none: 0,
    exclusive: 1,
    ondemand: 2,
};
export type Options = {
    anchor: Array<Edge>;
    layer: number;
    monitor: number;
    keyboardMode: number;
    namespace: string;
    margin: [number, number, number, number];
    exclusiveZone: number;
    autoExclusiveZone: boolean;
    backgroundTransparent: boolean;
    hidden: boolean;
};

export function init(options: Partial<Options> = {}): Promise<void> {
    const opt: any = {
        anchor: options.anchor?.map((e) => EdgeToNumber[e]) ?? [],
        layer: options.layer !== undefined ? LayersToNumber[options.layer] : 0,
        monitor: options.monitor !== undefined ? options.monitor : 0,
        keyboardMode:
            options.keyboardMode !== undefined ? KeyboardModeToNumber[options.keyboardMode] : 0,
        namespace: options.namespace ?? "mika-shell",
        margin: options.margin ?? [0, 0, 0, 0],
        exclusiveZone: options.exclusiveZone ?? 0,
        autoExclusiveZone: options.autoExclusiveZone ?? false,
        backgroundTransparent: options.backgroundTransparent ?? false,
        hidden: options.hidden ?? false,
    };

    return call("layer.init", opt);
}
export function show(): Promise<void> {
    return call("layer.show");
}
export function hide(): Promise<void> {
    return call("layer.hide");
}
export function close(): Promise<void> {
    return call("layer.close");
}
export function openDevTools(): Promise<void> {
    return call("layer.openDevTools");
}
export function resetAnchor(): Promise<void> {
    return call("layer.resetAnchor");
}
export function setAnchor(edge: Edge, anchor: boolean): Promise<void> {
    return call("layer.setAnchor", EdgeToNumber[edge], anchor);
}
export function setLayer(layer: Layers): Promise<void> {
    return call("layer.setLayer", LayersToNumber[layer]);
}
export function setKeyboardMode(mode: KeyboardMode): Promise<void> {
    return call("layer.setKeyboardMode", KeyboardModeToNumber[mode]);
}
export function setNamespace(namespace: string): Promise<void> {
    return call("layer.setNamespace", namespace);
}
export function setMargin(edge: Edge, margin: number): Promise<void> {
    return call("layer.setMargin", EdgeToNumber[edge], margin);
}
export function setExclusiveZone(zone: number): Promise<void> {
    return call("layer.setExclusiveZone", zone);
}
export function autoExclusiveZoneEnable(): Promise<void> {
    return call("layer.autoExclusiveZoneEnable");
}
