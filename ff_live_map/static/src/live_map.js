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
        this.infoWindow = new this.InfoWindowClass();
        this.state.mapError = "";
    }

    mapsFailed(message) {
        // No toast: a refresh landing mid-load would pop one every time. The
        // banner on the map says the same thing and disappears once it works.
        this.mapPromise = null;
        this.state.mapError = message;
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
        const visible = new Set();
        const bounds = new this.core.LatLngBounds();
        let count = 0;
        for (const person of this.located) {
            visible.add(person.id);
            const position = { lat: person.lat, lng: person.lng };
            let marker = this.markers.get(person.id);
            if (marker) {
                marker.setPosition(position);
                marker.setIcon(this.markerIcon(person));
            } else {
                marker = new this.MarkerClass({
                    map: this.map,
                    position,
                    title: person.name,
                    icon: this.markerIcon(person),
                    zIndex: 10,
                });
                marker.addListener("click", () => this.select(person));
                this.markers.set(person.id, marker);
            }
            marker.setLabel(
                this.state.showLabels
                    ? { text: person.name, className: "ff_live_map_label", color: "#0F1B3D", fontSize: "11px" }
                    : null
            );
            bounds.extend(position);
            count++;
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
        const seen = new Set();
        for (const client of wanted) {
            seen.add(client.id);
            if (this.clientMarkers.has(client.id)) {
                continue;
            }
            const marker = new this.MarkerClass({
                map: this.map,
                position: { lat: client.lat, lng: client.lng },
                title: client.name,
                zIndex: 1,
                icon: {
                    path: this.core.SymbolPath.CIRCLE,
                    scale: 6,
                    fillColor: "#7C5CFC",
                    fillOpacity: 1,
                    strokeColor: "#FFFFFF",
                    strokeWeight: 2,
                },
            });
            marker.addListener("click", () => {
                this.infoWindow.setContent(
                    `<div class="ff_live_map_info"><strong>${client.name}</strong><div class="text-muted">${client.category || "Customer"}</div></div>`
                );
                this.infoWindow.open({ map: this.map, anchor: marker });
            });
            this.clientMarkers.set(client.id, marker);
        }
        for (const [id, marker] of this.clientMarkers) {
            if (!seen.has(id)) {
                marker.setMap(null);
                this.clientMarkers.delete(id);
            }
        }
    }

    async toggleClients(ev) {
        this.state.showClients = ev.target.checked;
        await this.load();
    }

    toggleLabels(ev) {
        this.state.showLabels = ev.target.checked;
        this.drawMarkers();
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
