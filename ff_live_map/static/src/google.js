/** @odoo-module **/

import { loadJS } from "@web/core/assets";

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
    pending = pending || build(key);
    return pending;
}

async function build(key) {
    if (!window.google || !window.google.maps) {
        await loadJS(
            `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&loading=async&callback=Function.prototype`
        );
    }
    const maps = window.google.maps;
    if (typeof maps.importLibrary !== "function") {
        // An older loader already has everything on the namespace.
        return { Map: maps.Map, Marker: maps.Marker, InfoWindow: maps.InfoWindow, core: maps };
    }
    const [library, markers, core] = await Promise.all([
        maps.importLibrary("maps"),
        maps.importLibrary("marker"),
        maps.importLibrary("core"),
    ]);
    return {
        Map: library.Map || maps.Map,
        InfoWindow: library.InfoWindow || maps.InfoWindow,
        Marker: markers.Marker || maps.Marker,
        core: {
            Size: core.Size || maps.Size,
            Point: core.Point || maps.Point,
            LatLngBounds: core.LatLngBounds || maps.LatLngBounds,
            SymbolPath: core.SymbolPath || maps.SymbolPath,
        },
    };
}

/** Forget the loaded classes, so a failed attempt can be retried. */
export function resetGoogleMaps() {
    pending = null;
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
