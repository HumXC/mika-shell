<script lang="ts">
    import { Layer } from "@humxc/mikami";
    import { Application, Apps, InitApps } from "./common";
    import ByCategory from "./category/ByCategory.svelte";
    import { convertToPinyin } from "tiny-pinyin";
    import SideControler from "./sidebar/SideControler.svelte";
    import { slide } from "svelte/transition";
    import Tiles from "./tiles/Tiles.svelte";
    import { MountTile } from "./tiles/utils";
    import { Config, InitConfig, Sleep } from "../../utils";
    let apps: Application[] = [];
    let appsByCategory: Map<string, Application[]> = new Map();
    let appsByName: Map<string, Application[]> = new Map();
    let browserState: string = "name";
    async function loadApps() {
        apps = Array.from(Apps.values());
        appsByName = apps.reduce((acc, app) => {
            const name = app.Name || "";
            const firstChar = name[0] || "";
            const py = convertToPinyin(firstChar);
            let letter = py?.[0]?.[0]?.toUpperCase?.() || "#";
            if (!/^[A-Z]$/.test(letter)) {
                letter = "#";
            }
            if (!acc.has(letter)) {
                acc.set(letter, []);
            }
            acc.get(letter)!.push(app);
            return acc;
        }, appsByName);
        appsByName = appsByName;
        appsByCategory = apps.reduce((acc, app) => {
            const category = app.Categories || ["Others"];
            for (const cat of category) {
                if (!acc.has(cat)) {
                    acc.set(cat, []);
                }
                acc.get(cat)!.push(app);
            }
            return acc;
        }, appsByCategory);
        appsByCategory = appsByCategory;
    }
    Layer.Init({
        Height: 100,
        Anchor: ["top", "right", "left", "bottom"],
        Layer: "top",
        AutoExclusiveZoneEnable: true,
        KeyboardMode: "exclusive",
    });

    document.addEventListener("keydown", (e) => {
        if (e.code === "Escape") Layer.Close();
        if (e.code == "Tab") {
            if (browserState === "hide") {
                browserState = "name";
            }
        }
    });
    async function onTilesLoaded() {
        await InitApps();
        await loadApps();
        await InitConfig();
        Config["app-launcher"].tiles.forEach((tile, i) => {
            MountTile(tile, i);
        });
    }
</script>

<div class="w-full h-full flex">
    <!-- side -->
    <div class="h-full">
        <SideControler bind:state={browserState} />
    </div>

    <!-- browser -->
    {#if browserState !== "hide"}
        <div class="browser w-60 h-full" transition:slide={{ duration: 120, axis: "x" }}>
            {#if browserState === "name"}
                <ByCategory apps={appsByName} />
            {:else if browserState === "tags"}
                <ByCategory apps={appsByCategory} />
            {/if}
        </div>
    {/if}

    <!-- tiles -->
    <div class="tiles flex-1">
        <Tiles onLoaded={onTilesLoaded} />
    </div>
</div>

<style>
    .browser {
        background-color: rgb(8, 14, 24);
        color: rgb(198, 198, 198);
    }
    .tiles {
        background-color: rgb(8, 11, 23);
    }
</style>
