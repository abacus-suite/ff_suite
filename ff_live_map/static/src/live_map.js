/** @odoo-module **/

import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { loadMaps, pinIcon } from "@ff_live_map/google";
import { Component, onWillStart, onWillUnmount, useRef, useState, onMounted } from "@odoo/owl";

const REFRESH_MS = 30000;

const STATES = {
    moving: { label: "On the move", color: "#16A34A" },
    at_client: { label: "At a customer", color: "#1A56DB" },
    inactive: { label: "Not moving", color: "#F59E0B" },
    no_signal: { label: "No signal", color: "#DC2626" },
    off: { label: "Not punched in", color: "#94A3B8" },
};

/** "3 min ago" from an ISO timestamp. */
function since(iso) {
    if (!iso) {
        return "never";
    }
    const minutes = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
    if (minutes < 1) {
        return "just now";
    }
    if (minutes < 60) {
        return `${minutes} min ago`;
    }
    const hours = Math.floor(minutes / 60);
    return hours < 24 ? `${hours} h ago` : `${Math.floor(hours / 24)} d ago`;
}

/** The bubble the phone app draws: a soft halo, a gradient face and a count. */
function bubbleHtml(count, kind) {
    const text = count > 999 ? "999+" : String(count);
    const size = count >= 100 ? 54 : count >= 50 ? 50 : count >= 10 ? 46 : 42;
    return `<div class="ff_map_bubble ff_map_bubble_${kind}" style="--ff-bubble: ${size}px">
        <span class="ff_map_bubble_ring"></span>
        <span class="ff_map_bubble_face">${text}</span>
    </div>`;
}

/** A round bubble with a number in it, used for a group of pins. */
function bubbleIcon(count, colour, core) {
    const text = count > 999 ? "999+" : String(count);
    const size = count >= 100 ? 54 : count >= 50 ? 50 : count >= 10 ? 46 : 42;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size + 14}" height="${size + 14}">
        <circle cx="${(size + 14) / 2}" cy="${(size + 14) / 2}" r="${size / 2 + 6}" fill="${colour}" opacity="0.18"/>
        <circle cx="${(size + 14) / 2}" cy="${(size + 14) / 2}" r="${size / 2}" fill="${colour}"
                stroke="#ffffff" stroke-width="3"/>
        <text x="${(size + 14) / 2}" y="${(size + 14) / 2 + 5}" text-anchor="middle"
              font-family="Inter, sans-serif" font-size="${text.length > 3 ? 13 : 15}"
              font-weight="800" fill="#ffffff">${text}</text>
    </svg>`;
    return {
        url: "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(svg),
        scaledSize: new core.Size(size + 14, size + 14),
        anchor: new core.Point((size + 14) / 2, (size + 14) / 2),
    };
}

/** Groups points that sit within ``pixels`` of each other at this zoom. */
function clusterAt(rows, zoom, pixels = 70) {
    const scale = 256 * Math.pow(2, zoom);
    const points = rows
        .filter((row) => row.lat && row.lng)
        .map((row) => {
            const x = ((row.lng + 180) / 360) * scale;
            const sin = Math.min(Math.max(Math.sin((row.lat * Math.PI) / 180), -0.9999), 0.9999);
            const y = (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * scale;
            return { row, x, y };
        });
    const taken = new Set();
    const clusters = [];
    for (let i = 0; i < points.length; i++) {
        if (taken.has(i)) {
            continue;
        }
        const members = [];
        let sumLat = 0;
        let sumLng = 0;
        for (let j = i; j < points.length; j++) {
            if (taken.has(j)) {
                continue;
            }
            const dx = points[j].x - points[i].x;
            const dy = points[j].y - points[i].y;
            if (Math.sqrt(dx * dx + dy * dy) > pixels) {
                continue;
            }
            taken.add(j);
            members.push(points[j].row);
            sumLat += points[j].row.lat;
            sumLng += points[j].row.lng;
        }
        clusters.push({
            lat: sumLat / members.length,
            lng: sumLng / members.length,
            members,
        });
    }
    return clusters;
}

export class FieldForceLiveMap extends Component {
    static template = "ff_live_map.LiveMap";
    // Client actions receive action, actionId, className... from the action service.
    static props = { "*": true };

    setup() {
        this.orm = useService("orm");
        this.notification = useService("notification");
        this.action = useService("action");
        this.mapRef = useRef("map");
        this.state = useState({
            people: [],
            filter: "all",
            search: "",
            selectedId: null,
            hasKey: false,
            mapError: "",
            loading: true,
            updatedAt: "",
            usage: null,
            clients: [],
            groupPins: true,
            showClients: false,
            showLabels: true,
        });
        this.clientMarkers = new Map();
        this.markers = new Map();
        this.mapsKey = "";
        this.mounted = false;

        onWillStart(async () => {
            await this.load();
        });
        onMounted(async () => {
            // The map div only exists once we are in the DOM.
            this.mounted = true;
            if (this.state.hasKey) {
                await this.ensureMap(this.mapsKey);
                this.drawMarkers();
            }
            this.timer = setInterval(() => this.load(), REFRESH_MS);
        });
        onWillUnmount(() => {
            clearInterval(this.timer);
        });
    }

    get located() {
        return this.visiblePeople.filter((p) => p.lat && p.lng);
    }

    get visiblePeople() {
        const term = this.state.search.trim().toLowerCase();
        return this.state.people.filter((person) => {
            const filter = this.state.filter;
            let byState = filter === "all" || person.state === filter;
            if (filter === "in") {
                byState = person.punched_in;
            }
            const byTerm =
                !term ||
                (person.name || "").toLowerCase().includes(term) ||
                (person.team || "").toLowerCase().includes(term) ||
                (person.at_client || "").toLowerCase().includes(term);
            return byState && byTerm;
        });
    }

    get counts() {
        const counts = { all: this.state.people.length };
        for (const key of Object.keys(STATES)) {
            counts[key] = this.state.people.filter((p) => p.state === key).length;
        }
        counts.in = this.state.people.filter((p) => p.punched_in).length;
        return counts;
    }

    get legend() {
        return Object.entries(STATES).map(([key, value]) => ({ key, ...value }));
    }

    /// How many of each kind are on the map right now.
    get onMap() {
        const clients = this.state.showClients ? (this.state.clients || []).filter((c) => c.lat && c.lng) : [];
        return { people: this.located.length, clients: clients.length };
    }

    /// Pins grouped into counted bubbles, or every pin on its own.
    toggleGrouping() {
        this.state.groupPins = this.state.groupPins === false;
        this.markers.forEach((marker) => marker.setMap(null));
        this.markers.clear();
        this.clientMarkers.forEach((marker) => marker.setMap(null));
        this.clientMarkers.clear();
        this.drawMarkers();
    }

    /// "10:44 AM" from an ISO timestamp.
    clock(iso) {
        return iso ? new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : "";
    }

    stateLabel(key) {
        return (STATES[key] || STATES.off).label;
    }

    stateColor(key) {
        return (STATES[key] || STATES.off).color;
    }

    lastSeen(person) {
        return since(person.last_ping_at);
    }

    async load() {
        const data = await this.orm.call("ff.employee.status", "ff_live_map", [this.state.showClients]);
        this.state.people = data.people;
        this.state.clients = data.clients || [];
        this.mapsKey = data.google_maps_key;
        this.mapProvider = data.map_provider || (data.google_maps_key ? "google" : "open");
        this.mapStyle = data.map_style;
        // Free maps need no key, so there is always something to draw.
        this.state.hasKey = this.mapProvider === "open" || Boolean(data.google_maps_key);
        this.state.loading = false;
        this.state.updatedAt = new Date().toLocaleTimeString();
        if (!this.state.usage) {
            this.state.usage = await this.orm.call("ff.map.usage", "ff_usage_summary", []);
        }
        if (this.mounted && this.state.hasKey) {
            await this.ensureMap(this.mapsKey);
            this.drawMarkers();
        }
    }

    /** Build the map once. Concurrent callers wait on the same promise. */
    async ensureMap(key) {
        if (this.map) {
            return;
        }
        this.mapPromise = this.mapPromise || this.buildMap(key);
        await this.mapPromise;
    }

    async buildMap(key) {
        let classes;
        try {
            classes = await loadMaps(this.mapProvider, key, this.mapStyle);
        } catch (error) {
            this.mapsFailed(error.message || String(error));
            return;
        }
        this.MapClass = classes.Map;
        this.InfoWindowClass = classes.InfoWindow;
        this.MarkerClass = classes.Marker;
        this.core = classes.core;
        if (!this.mapRef.el) {
            // Not in the DOM yet: let the next call build it.
            this.mapPromise = null;
            return;
        }
        // One Google "map load" is billed here, so count it here too (free maps cost nothing).
        if (classes.provider === "google") {
            this.state.usage = await this.orm.call("ff.map.usage", "ff_record_web_map", []);
        }
        this.map = new this.MapClass(this.mapRef.el, {
            center: { lat: 20.5937, lng: 78.9629 },
            zoom: 5,
            mapTypeControl: true,
            streetViewControl: false,
            fullscreenControl: true,
            clickableIcons: false,
        });
        // MapLibre places a marker only once its style is up: markers added
        // before that sit in the corner of the map instead of on their place.
        if (this.map.whenReady) {
            await this.map.whenReady();
        }
        this.infoWindow = new this.InfoWindowClass();
        // Pins regroup once the map settles, so a bubble always counts what is
        // really under it at this zoom.
        if (this.map.addListener) {
            this.map.addListener("idle", () => {
                const zoom = this.map.getZoom ? Math.round(this.map.getZoom() * 4) : 0;
                if (zoom !== this.lastZoomStep) {
                    this.lastZoomStep = zoom;
                    this.drawMarkers();
                }
            });
        }
        this.state.mapError = "";
    }

    mapsFailed(message) {
        // No toast: a refresh landing mid-load would pop one every time. The
        // banner on the map says the same thing and disappears once it works.
        this.mapPromise = null;
        this.state.mapError = message;
    }

    /// The counted bubble: a live element on the free map, a picture on Google's.
    bubble(count, kind) {
        if (this.mapProvider !== "google") {
            return { html: bubbleHtml(count, kind), anchor: "center" };
        }
        return bubbleIcon(count, kind === "people" ? "#1A56DB" : "#0F9D8C", this.core);
    }

    markerIcon(person) {
        return pinIcon(this.stateColor(person.state), this.core);
    }

    infoHtml(person) {
        const rows = [
            person.job || person.code,
            person.team && `Team: ${person.team}`,
            person.at_client && `At ${person.at_client}`,
            `Last seen ${since(person.last_ping_at)}`,
            person.battery ? `Battery ${person.battery}%` : "",
            person.phone,
        ].filter(Boolean);
        return `<div class="ff_live_map_info">
            <strong>${person.name}</strong>
            <div class="text-muted">${this.stateLabel(person.state)}</div>
            ${rows.map((row) => `<div>${row}</div>`).join("")}
        </div>`;
    }

    drawMarkers() {
        if (!this.map) {
            return;
        }
        const zoom = this.map.getZoom ? this.map.getZoom() : 12;
        const clusters = this.state.groupPins === false ? this.located.map((p) => ({ lat: p.lat, lng: p.lng, members: [p] })) : clusterAt(this.located, zoom);
        const visible = new Set();
        const bounds = new this.core.LatLngBounds();
        let count = 0;
        for (const cluster of clusters) {
            const single = cluster.members.length === 1;
            const person = cluster.members[0];
            const id = single ? `p${person.id}` : `g${Math.round(cluster.lat * 1e4)}:${Math.round(cluster.lng * 1e4)}:${cluster.members.length}`;
            visible.add(id);
            const position = { lat: cluster.lat, lng: cluster.lng };
            let marker = this.markers.get(id);
            const icon = single
                ? this.markerIcon(person)
                : this.bubble(cluster.members.length, "people");
            if (marker) {
                marker.setPosition(position);
                marker.setIcon(icon);
            } else {
                marker = new this.MarkerClass({
                    map: this.map,
                    position,
                    title: single ? person.name : `${cluster.members.length} employees`,
                    icon,
                    zIndex: single ? 10 : 20,
                });
                marker.addListener("click", () => {
                    if (single) {
                        this.select(person);
                    } else {
                        // Open the group: zoom in on what it holds.
                        this.map.setCenter(position);
                        this.map.setZoom(Math.min((this.map.getZoom ? this.map.getZoom() : 12) + 2, 17));
                        this.drawMarkers();
                    }
                });
                this.markers.set(id, marker);
            }
            // Names only once the map is close enough for them to mean something.
            marker.setLabel(
                this.state.showLabels && single && zoom >= 9
                    ? { text: person.name, className: "ff_live_map_label", color: "#0F1B3D", fontSize: "11px" }
                    : null
            );
            bounds.extend(position);
            count += cluster.members.length;
        }
        this.drawClients();
        for (const [id, marker] of this.markers) {
            if (!visible.has(id)) {
                marker.setMap(null);
                this.markers.delete(id);
            }
        }
        if (count && !this.fitted) {
            this.fitted = true;
            if (count === 1) {
                this.map.setCenter(bounds.getCenter());
                this.map.setZoom(15);
            } else {
                this.map.fitBounds(bounds, 60);
            }
        }
    }

    drawClients() {
        if (!this.map) {
            return;
        }
        const wanted = this.state.showClients ? this.state.clients : [];
        const zoom = this.map.getZoom ? this.map.getZoom() : 12;
        const clusters = this.state.groupPins === false ? wanted.filter((c) => c.lat && c.lng).map((c) => ({ lat: c.lat, lng: c.lng, members: [c] })) : clusterAt(wanted, zoom);
        const seen = new Set();
        for (const cluster of clusters) {
            const single = cluster.members.length === 1;
            const client = cluster.members[0];
            const id = single ? `c${client.id}` : `cg${Math.round(cluster.lat * 1e4)}:${Math.round(cluster.lng * 1e4)}:${cluster.members.length}`;
            seen.add(id);
            if (this.clientMarkers.has(id)) {
                continue;
            }
            const position = { lat: cluster.lat, lng: cluster.lng };
            const marker = new this.MarkerClass({
                map: this.map,
                position,
                title: single ? client.name : `${cluster.members.length} customers`,
                icon: single
                    ? pinIcon("#14B8A6", this.core)
                    : this.bubble(cluster.members.length, "clients"),
                zIndex: single ? 5 : 6,
            });
            marker.addListener("click", () => {
                if (!single) {
                    this.map.setCenter(position);
                    this.map.setZoom(Math.min((this.map.getZoom ? this.map.getZoom() : 12) + 2, 17));
                    this.drawClients();
                    return;
                }
                this.infoWindow.setContent(`<div class="ff_live_map_info">
                    <strong>${client.name}</strong>
                    <div class="text-muted">${client.address || ""}</div>
                    ${client.phone ? `<div>${client.phone}</div>` : ""}
                </div>`);
                this.infoWindow.open({ map: this.map, anchor: marker });
            });
            this.clientMarkers.set(id, marker);
        }
        for (const [id, marker] of this.clientMarkers) {
            if (!seen.has(id)) {
                marker.setMap(null);
                this.clientMarkers.delete(id);
            }
        }
    }

    select(person) {
        this.state.selectedId = person.id;
        const marker = this.markers.get(person.id);
        if (marker && this.map) {
            this.map.panTo(marker.getPosition());
            if (this.map.getZoom() < 14) {
                this.map.setZoom(15);
            }
            this.infoWindow.setContent(this.infoHtml(person));
            this.infoWindow.open({ map: this.map, anchor: marker });
        } else if (!person.lat) {
            this.notification.add(`${person.name} has not sent a location yet.`, { type: "warning" });
        }
    }

    openTimeline(person) {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: `${person.name} - today`,
            res_model: "ff.location.ping",
            views: [
                [false, "list"],
                [false, "form"],
            ],
            domain: [["employee_id", "=", person.id]],
            context: { search_default_today: 1 },
        });
    }

    setFilter(key) {
        this.state.filter = key;
        this.fitted = false;
        this.drawMarkers();
    }

    onSearch(ev) {
        this.state.search = ev.target.value;
        this.drawMarkers();
    }

    openUsage() {
        this.action.doAction({ type: "ir.actions.client", tag: "ff_map_cost", name: "Map Cost" });
    }

    openSettings() {
        this.action.doAction({
            type: "ir.actions.act_window",
            res_model: "res.config.settings",
            views: [[false, "form"]],
            target: "current",
            context: { module: "ff_base" },
        });
    }
}

registry.category("actions").add("ff_live_map", FieldForceLiveMap);
