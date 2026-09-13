/** @odoo-module **/

import { loadJS } from "@web/core/assets";
import { loadOpenMaps } from "./open_maps";

/**
 * Load the Google Maps classes once for the whole backend.
 *
 * The async loader hands the classes back from importLibrary and makes no
 * promise about hanging them on window.google.maps, so callers get what it
 * returned. Everybody shares one promise: two screens opening together, or a
 * refresh landing mid-load, wait rather than start a second load.
 */
let pending = null;

export function loadGoogleMaps(key) {
    pending = pending || build(key).catch((error) => {
        pending = null; // let the next attempt try again
        throw error;
    });
    return pending;
}

/**
 * The map classes for the provider chosen in settings: Google's, or the free
 * MapLibre / OpenFreeMap ones shaped the same way.
 */
export function loadMaps(provider, key, style) {
    if (provider === "google") {
        return loadGoogleMaps(key).then((classes) => ({ provider: "google", ...classes }));
    }
    return loadOpenMaps(style);
}

/** Forget the loaded classes, so a failed attempt can be retried. */
export function resetGoogleMaps() {
    pending = null;
}

async function build(key) {
    if (!window.google || !window.google.maps) {
        await loadJS(
            `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&loading=async&callback=Function.prototype`
        );
    }
    // The script tag can resolve a moment before the bootstrap has installed
    // anything, so wait for one of the two shapes rather than assuming.
    const maps = await waitFor(
        () => window.google && window.google.maps,
        (value) => typeof value.importLibrary === "function" || typeof value.Map === "function"
    );

    let classes;
    if (typeof maps.importLibrary === "function") {
        const [library, markers, core] = await Promise.all([
            maps.importLibrary("maps"),
            maps.importLibrary("marker"),
            maps.importLibrary("core"),
        ]);
        classes = {
            Map: library.Map || maps.Map,
            InfoWindow: library.InfoWindow || maps.InfoWindow,
            Marker: markers.Marker || maps.Marker,
            Polyline: library.Polyline || maps.Polyline,
            core: {
                Size: core.Size || maps.Size,
                Point: core.Point || maps.Point,
                LatLngBounds: core.LatLngBounds || maps.LatLngBounds,
                SymbolPath: core.SymbolPath || maps.SymbolPath,
            },
        };
    } else {
        classes = {
            Map: maps.Map,
            InfoWindow: maps.InfoWindow,
            Marker: maps.Marker,
            Polyline: maps.Polyline,
            core: maps,
        };
    }
    if (typeof classes.Map !== "function") {
        throw new Error(
            "Google returned no map class. Check that billing is on, the Maps JavaScript API is " +
                "enabled, and the key's restrictions allow this domain."
        );
    }
    return classes;
}

/** Poll briefly for something the loader installs asynchronously. */
async function waitFor(get, ready, timeout = 10000) {
    const deadline = Date.now() + timeout;
    for (;;) {
        const value = get();
        if (value && ready(value)) {
            return value;
        }
        if (Date.now() > deadline) {
            throw new Error("Google Maps did not finish loading in time.");
        }
        await new Promise((resolve) => setTimeout(resolve, 100));
    }
}

/** The teardrop pin used for people on every map. */
export function pinIcon(color, core) {
    const svg = `
        <svg xmlns="http://www.w3.org/2000/svg" width="34" height="46" viewBox="0 0 34 46">
          <path d="M17 45C17 45 32 27.5 32 16.5A15 15 0 1 0 2 16.5C2 27.5 17 45 17 45Z"
                fill="${color}" stroke="white" stroke-width="2.5"/>
          <circle cx="17" cy="16" r="5.5" fill="white"/>
        </svg>`;
    return {
        url: "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(svg.trim()),
        scaledSize: new core.Size(34, 46),
        anchor: new core.Point(17, 46),
    };
}
