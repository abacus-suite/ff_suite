/** @odoo-module **/

import { loadCSS, loadJS } from "@web/core/assets";

/**
 * Free maps for the backend: MapLibre GL drawing OpenFreeMap vector tiles.
 *
 * The live map and the panel were written against Google's classes, so this
 * file hands back the same small set - Map, Marker, InfoWindow, Polyline and
 * core.LatLngBounds / Size / Point / SymbolPath - with the methods those
 * screens call. Switching provider in settings changes the loader, not the
 * screens. No key, no account and no per-view charge.
 */
const MAPLIBRE = "https://cdn.jsdelivr.net/npm/maplibre-gl@4.7.1/dist/maplibre-gl";
const STYLES = {
    liberty: "https://tiles.openfreemap.org/styles/liberty",
    positron: "https://tiles.openfreemap.org/styles/positron",
    bright: "https://tiles.openfreemap.org/styles/bright",
};

let pending = null;

export function loadOpenMaps(style) {
    pending = pending || build(style).catch((error) => {
        pending = null;
        throw error;
    });
    return pending;
}

async function build(style) {
    if (!window.maplibregl) {
        await Promise.all([loadCSS(`${MAPLIBRE}.css`), loadJS(`${MAPLIBRE}.js`)]);
    }
    const gl = window.maplibregl;
    if (!gl || typeof gl.Map !== "function") {
        throw new Error("The free map library could not be loaded. Check the internet connection.");
    }
    return classesFor(gl, STYLES[style] || STYLES.liberty);
}

let lineCounter = 0;

function classesFor(gl, styleUrl) {
    class LatLng {
        constructor(lat, lng) {
            this._lat = lat;
            this._lng = lng;
        }
        lat() {
            return this._lat;
        }
        lng() {
            return this._lng;
        }
    }

    const toLatLng = (p) =>
        p instanceof LatLng ? p : new LatLng(typeof p.lat === "function" ? p.lat() : p.lat, typeof p.lng === "function" ? p.lng() : p.lng);

    class Size {
        constructor(width, height) {
            this.width = width;
            this.height = height;
        }
    }

    class Point {
        constructor(x, y) {
            this.x = x;
            this.y = y;
        }
    }

    const SymbolPath = { CIRCLE: "circle", FORWARD_CLOSED_ARROW: "arrow" };

    class LatLngBounds {
        constructor() {
            this.south = Infinity;
            this.west = Infinity;
            this.north = -Infinity;
            this.east = -Infinity;
        }
        extend(point) {
            const p = toLatLng(point);
            this.south = Math.min(this.south, p.lat());
            this.north = Math.max(this.north, p.lat());
            this.west = Math.min(this.west, p.lng());
            this.east = Math.max(this.east, p.lng());
            return this;
        }
        isEmpty() {
            return this.south === Infinity;
        }
        getCenter() {
            return new LatLng((this.south + this.north) / 2, (this.west + this.east) / 2);
        }
    }

    class OpenMap {
        constructor(element, options = {}) {
            this.element = element;
            const center = options.center || { lat: 20.5937, lng: 78.9629 };
            this.gl = new gl.Map({
                container: element,
                style: styleUrl,
                center: [center.lng, center.lat],
                zoom: options.zoom ?? 5,
                attributionControl: false,
            });
            this.gl.addControl(new gl.NavigationControl({ showCompass: false }), "bottom-right");
            if (options.fullscreenControl !== false) {
                this.gl.addControl(new gl.FullscreenControl(), "top-right");
            }
            this.ready = new Promise((resolve) => {
                if (this.gl.loaded()) {
                    resolve();
                } else {
                    this.gl.once("load", resolve);
                }
            });
            // A map built while its box is still being laid out draws at the wrong size.
            setTimeout(() => this.gl.resize(), 150);
        }
        getDiv() {
            return this.element;
        }
        getZoom() {
            return this.gl.getZoom();
        }
        setZoom(zoom) {
            this.gl.easeTo({ zoom });
        }
        setCenter(point) {
            const p = toLatLng(point);
            this.gl.jumpTo({ center: [p.lng(), p.lat()] });
        }
        panTo(point) {
            const p = toLatLng(point);
            this.gl.easeTo({ center: [p.lng(), p.lat()] });
        }
        fitBounds(bounds, padding = 40) {
            if (!bounds || bounds.isEmpty()) {
                return;
            }
            if (bounds.south === bounds.north && bounds.west === bounds.east) {
                this.gl.jumpTo({ center: [bounds.west, bounds.south], zoom: 15 });
                return;
            }
            this.gl.fitBounds(
                [
                    [bounds.west, bounds.south],
                    [bounds.east, bounds.north],
                ],
                { padding: typeof padding === "number" ? padding : 40, maxZoom: 16, duration: 0 }
            );
        }
    }

    /** Draws Google-style icons (an image, or a circle / arrow symbol) as HTML. */
    function paintIcon(box, icon) {
        box.innerHTML = "";
        if (!icon) {
            const dot = document.createElement("div");
            dot.style.cssText = "width:14px;height:14px;border-radius:50%;background:#1a56db;border:2px solid #fff";
            box.appendChild(dot);
            return { anchor: "center" };
        }
        if (icon.url) {
            const img = document.createElement("img");
            img.src = icon.url;
            const size = icon.scaledSize || new Size(34, 46);
            img.style.width = `${size.width}px`;
            img.style.height = `${size.height}px`;
            img.style.display = "block";
            box.appendChild(img);
            return { anchor: "bottom" };
        }
        const scale = icon.scale || 6;
        const fill = icon.fillColor || "#1a56db";
        const stroke = icon.strokeColor || "#fff";
        const weight = icon.strokeWeight ?? 2;
        if (icon.path === SymbolPath.FORWARD_CLOSED_ARROW) {
            const size = scale * 4;
            box.innerHTML = `<svg width="${size}" height="${size}" viewBox="-6 -6 12 12"
                style="display:block;transform:rotate(${icon.rotation || 0}deg)">
                <path d="M0 -5 L4 4 L0 2 L-4 4 Z" fill="${fill}" stroke="${stroke}" stroke-width="${weight / 3}"/></svg>`;
        } else {
            const size = scale * 2;
            const dot = document.createElement("div");
            dot.style.cssText = `width:${size}px;height:${size}px;border-radius:50%;background:${fill};` +
                `opacity:${icon.fillOpacity ?? 1};border:${weight}px solid ${stroke};box-sizing:content-box`;
            box.appendChild(dot);
        }
        return { anchor: "center" };
    }

    class Marker {
        constructor(options = {}) {
            this.root = document.createElement("div");
            this.root.className = "ff_open_marker";
            this.root.style.cursor = "pointer";
            this.root.style.position = "relative";
            this.iconBox = document.createElement("div");
            this.root.appendChild(this.iconBox);
            this.labelBox = document.createElement("div");
            this.labelBox.className = "ff_open_marker_label";
            this.root.appendChild(this.labelBox);
            if (options.title) {
                this.root.title = options.title;
            }
            this.root.style.zIndex = options.zIndex || 1;
            this.listeners = [];
            this.icon = options.icon;
            this.position = toLatLng(options.position || { lat: 0, lng: 0 });
            const { anchor } = paintIcon(this.iconBox, this.icon);
            this.anchor = anchor;
            this.gl = new gl.Marker({ element: this.root, anchor });
            this.gl.setLngLat([this.position.lng(), this.position.lat()]);
            this.setLabel(options.label || null);
            this.map = null;
            if (options.map) {
                this.setMap(options.map);
            }
        }
        setMap(map) {
            if (this.map === map) {
                return;
            }
            this.gl.remove();
            this.map = map || null;
            if (map) {
                this.gl.addTo(map.gl);
            }
        }
        getMap() {
            return this.map;
        }
        setPosition(point) {
            this.position = toLatLng(point);
            this.gl.setLngLat([this.position.lng(), this.position.lat()]);
        }
        getPosition() {
            return this.position;
        }
        setIcon(icon) {
            this.icon = icon;
            const { anchor } = paintIcon(this.iconBox, icon);
            if (anchor !== this.anchor) {
                // MapLibre fixes the anchor when the marker is made: rebuild it on the same map.
                const map = this.map;
                this.gl.remove();
                this.anchor = anchor;
                this.gl = new gl.Marker({ element: this.root, anchor });
                this.gl.setLngLat([this.position.lng(), this.position.lat()]);
                this.map = null;
                if (map) {
                    this.setMap(map);
                }
            }
        }
        getIcon() {
            return this.icon;
        }
        setLabel(label) {
            if (!label) {
                this.labelBox.style.display = "none";
                return;
            }
            const text = typeof label === "string" ? label : label.text;
            this.labelBox.textContent = text;
            // A person's name hangs under the pin; a stop number sits on the pin's head.
            const onPin = this.icon && this.icon.url && !(label && label.fontWeight);
            this.labelBox.style.cssText = onPin
                ? "display:block;position:absolute;left:50%;top:100%;transform:translateX(-50%);margin-top:2px;" +
                  "white-space:nowrap;background:#fff;border-radius:8px;padding:1px 7px;font-size:11px;font-weight:700;" +
                  `color:${(label && label.color) || "#0f1b3d"};box-shadow:0 2px 6px rgba(15,27,61,.18)`
                : `display:block;position:absolute;left:50%;top:${this.icon && this.icon.url ? "36%" : "50%"};transform:translate(-50%,-50%);` +
                  `font-size:${(label && label.fontSize) || "11px"};font-weight:${(label && label.fontWeight) || 700};` +
                  `color:${(label && label.color) || "#fff"};pointer-events:none`;
            if (onPin) {
                this.labelBox.style.top = "100%";
            }
        }
        addListener(event, handler) {
            if (event !== "click") {
                return { remove() {} };
            }
            const wrapped = (ev) => {
                ev.stopPropagation();
                handler(ev);
            };
            this.root.addEventListener("click", wrapped);
            return { remove: () => this.root.removeEventListener("click", wrapped) };
        }
    }

    class InfoWindow {
        constructor() {
            this.popup = new gl.Popup({ closeButton: true, offset: 30, maxWidth: "280px" });
            this.content = "";
        }
        setContent(html) {
            this.content = html;
            this.popup.setHTML(html);
        }
        open(options, anchorMarker) {
            const map = options && options.map ? options.map : options;
            const marker = options && options.anchor ? options.anchor : anchorMarker;
            if (!map || !marker) {
                return;
            }
            const p = marker.getPosition();
            this.popup.setOffset(marker.anchor === "bottom" ? [0, -44] : [0, -10]);
            this.popup.setLngLat([p.lng(), p.lat()]).setHTML(this.content).addTo(map.gl);
        }
        close() {
            this.popup.remove();
        }
    }

    class Polyline {
        constructor(options = {}) {
            this.id = `ff_line_${++lineCounter}`;
            this.options = options;
            this.map = null;
            if (options.map) {
                this.setMap(options.map);
            }
        }
        setMap(map) {
            if (this.map) {
                const old = this.map.gl;
                if (old.getLayer(this.id)) {
                    old.removeLayer(this.id);
                }
                if (old.getSource(this.id)) {
                    old.removeSource(this.id);
                }
            }
            this.map = map || null;
            if (!map) {
                return;
            }
            const draw = () => {
                if (this.map !== map || map.gl.getSource(this.id)) {
                    return;
                }
                const coordinates = (this.options.path || []).map((point) => {
                    const p = toLatLng(point);
                    return [p.lng(), p.lat()];
                });
                map.gl.addSource(this.id, {
                    type: "geojson",
                    data: { type: "Feature", geometry: { type: "LineString", coordinates } },
                });
                map.gl.addLayer({
                    id: this.id,
                    type: "line",
                    source: this.id,
                    layout: { "line-join": "round", "line-cap": "round" },
                    paint: {
                        "line-color": this.options.strokeColor || "#1a56db",
                        "line-width": this.options.strokeWeight || 4,
                        "line-opacity": this.options.strokeOpacity ?? 1,
                    },
                });
            };
            map.ready.then(draw);
        }
        getMap() {
            return this.map;
        }
    }

    return {
        provider: "open",
        Map: OpenMap,
        Marker,
        InfoWindow,
        Polyline,
        core: { Size, Point, LatLngBounds, SymbolPath },
    };
}
