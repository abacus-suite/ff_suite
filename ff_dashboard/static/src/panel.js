/** @odoo-module **/

import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { Component, onWillStart, onWillUnmount, useRef, useState } from "@odoo/owl";
import { loadGoogleMaps, pinIcon } from "@ff_live_map/google";

const REFRESH_MS = 60000;

/** The sidebar. More entries land here as each area of the panel is built. */
const SECTIONS = [
    { key: "dashboard", label: "Dashboard", icon: "fa-th-large" },
    { key: "live", label: "Live Location", icon: "fa-map-marker" },
];

/** Colour and wording for what somebody is doing right now. */
const STATES = {
    moving: { label: "On the move", color: "#16A34A" },
    at_client: { label: "At a customer", color: "#1A56DB" },
    inactive: { label: "Not moving", color: "#F59E0B" },
    no_signal: { label: "No signal", color: "#DC2626" },
    off: { label: "Not punched in", color: "#94A3B8" },
};

function ago(iso) {
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

export class AixoloPanel extends Component {
    static template = "ff_dashboard.Panel";
    static props = {};

    setup() {
        this.orm = useService("orm");
        this.action = useService("action");
        this.sections = SECTIONS;
        this.mapRef = useRef("liveMap");
        this.markers = new Map();
        this.clientMarkers = new Map();
        this.state = useState({
            section: "dashboard",
            live: null,
            liveError: "",
            liveSearch: "",
            liveFilter: "all",
            battery: "all",
            gps: "all",
            showClients: false,
            openId: null,
            liveView: "live",
            timeline: null,
            timelineEmployees: [],
            timelineEmployeeId: null,
            timelineDate: null,
            timelineLoading: false,
            playing: false,
            playIndex: 0,
            tab: "visits",
            day: null,
            dayLoading: false,
            period: "month",
            search: "",
            data: null,
            loading: true,
            updatedAt: "",
            collapsed: false,
        });

        onWillStart(() => this.load());
        this.timer = setInterval(() => this.load(), REFRESH_MS);
        onWillUnmount(() => {
            clearInterval(this.timer);
            clearInterval(this.playTimer);
        });
    }

    async load() {
        this.state.data = await this.orm.call("ff.dashboard", "ff_dashboard_data", [this.state.period]);
        this.state.loading = false;
        this.state.updatedAt = new Date().toLocaleTimeString();
        if (this.state.section === "live") {
            await this.loadLive();
        }
    }

    async setPeriod(period) {
        this.state.period = period;
        await this.load();
    }

    async openSection(key) {
        this.state.section = key;
        if (key === "live") {
            await this.loadLive();
        }
    }

    // -- Live Location ----------------------------------------------------
    async loadLive() {
        this.state.live = await this.orm.call("ff.employee.status", "ff_live_map", [
            this.state.showClients,
        ]);
        this.state.updatedAt = new Date().toLocaleTimeString();
        await this.drawLive();
    }

    get livePeople() {
        const live = this.state.live;
        if (!live) {
            return [];
        }
        const term = this.state.liveSearch.trim().toLowerCase();
        return live.people.filter((person) => {
            const filter = this.state.liveFilter;
            let byState = filter === "all" || person.state === filter;
            if (filter === "in") {
                byState = person.punched_in;
            }
            const byBattery =
                this.state.battery === "all" ||
                (this.state.battery === "low" ? person.battery && person.battery < 20 : person.battery >= 20);
            const byGps =
                this.state.gps === "all" ||
                (this.state.gps === "on" ? person.gps_on : !person.gps_on);
            const byTerm =
                !term ||
                (person.name || "").toLowerCase().includes(term) ||
                (person.code || "").toLowerCase().includes(term) ||
                (person.team || "").toLowerCase().includes(term) ||
                (person.address || "").toLowerCase().includes(term);
            return byState && byBattery && byGps && byTerm;
        });
    }

    get liveCounts() {
        const people = this.state.live ? this.state.live.people : [];
        const counts = { all: people.length, in: people.filter((p) => p.punched_in).length };
        for (const key of Object.keys(STATES)) {
            counts[key] = people.filter((p) => p.state === key).length;
        }
        return counts;
    }

    get legend() {
        return Object.entries(STATES).map(([key, value]) => ({ key, ...value }));
    }

    stateLabel(key) {
        return (STATES[key] || STATES.off).label;
    }

    stateColor(key) {
        return (STATES[key] || STATES.off).color;
    }

    setLiveFilter(key) {
        this.state.liveFilter = key;
        this.drawLive();
    }

    onLiveSearch(ev) {
        this.state.liveSearch = ev.target.value;
        this.drawLive();
    }

    setBattery(ev) {
        this.state.battery = ev.target.value;
        this.drawLive();
    }

    setGps(ev) {
        this.state.gps = ev.target.value;
        this.drawLive();
    }

    async toggleClients(ev) {
        this.state.showClients = ev.target.checked;
        await this.loadLive();
    }

    /** Open a card: load that person's day for the tabs, and centre the map. */
    async openPerson(person) {
        if (this.state.openId === person.id) {
            this.state.openId = null;
            return;
        }
        this.state.openId = person.id;
        this.state.tab = "visits";
        this.state.dayLoading = true;
        this.state.day = null;
        this.centreOn(person);
        this.state.day = await this.orm.call("ff.dashboard", "ff_employee_day", [person.id]);
        this.state.dayLoading = false;
    }

    setTab(tab) {
        this.state.tab = tab;
    }

    centreOn(person) {
        const marker = this.markers.get(person.id);
        if (!marker || !this.liveMap) {
            return;
        }
        this.liveMap.panTo(marker.getPosition());
        if (this.liveMap.getZoom() < 14) {
            this.liveMap.setZoom(15);
        }
    }

    async drawLive() {
        const live = this.state.live;
        if (!live || !live.google_maps_key) {
            return;
        }
        if (!this.google) {
            try {
                this.google = await loadGoogleMaps(live.google_maps_key);
                this.state.liveError = "";
            } catch (error) {
                this.state.liveError = error.message || String(error);
                return;
            }
        }
        if (!this.mapRef.el) {
            return;  // the section is not on screen yet
        }
        if (!this.liveMap) {
            this.state.usage = await this.orm.call("ff.map.usage", "ff_record_web_map", []);
            this.liveMap = new this.google.Map(this.mapRef.el, {
                center: { lat: 20.5937, lng: 78.9629 },
                zoom: 5,
                mapTypeControl: true,
                streetViewControl: false,
                clickableIcons: false,
            });
            this.liveInfo = new this.google.InfoWindow();
            this.state.liveError = "";
        }
        this.paintMarkers();
    }

    paintMarkers() {
        const shown = new Set();
        const bounds = new this.google.core.LatLngBounds();
        let count = 0;
        for (const person of this.livePeople.filter((p) => p.lat && p.lng)) {
            shown.add(person.id);
            const position = { lat: person.lat, lng: person.lng };
            let marker = this.markers.get(person.id);
            if (marker) {
                marker.setPosition(position);
                marker.setIcon(pinIcon(this.stateColor(person.state), this.google.core));
            } else {
                marker = new this.google.Marker({
                    map: this.liveMap,
                    position,
                    title: person.name,
                    zIndex: 10,
                    icon: pinIcon(this.stateColor(person.state), this.google.core),
                });
                marker.addListener("click", () => this.openPerson(person));
                this.markers.set(person.id, marker);
            }
            marker.setLabel({
                text: person.name,
                className: "ff_map_label",
                color: "#0F1B3D",
                fontSize: "11px",
            });
            bounds.extend(position);
            count++;
        }
        for (const [id, marker] of this.markers) {
            if (!shown.has(id)) {
                marker.setMap(null);
                this.markers.delete(id);
            }
        }
        this.paintClients();
        if (count && !this.fitted) {
            this.fitted = true;
            if (count === 1) {
                this.liveMap.setCenter(bounds.getCenter());
                this.liveMap.setZoom(15);
            } else {
                this.liveMap.fitBounds(bounds, 60);
            }
        }
    }

    paintClients() {
        const wanted = this.state.showClients && this.state.live ? this.state.live.clients : [];
        const shown = new Set();
        for (const client of wanted) {
            shown.add(client.id);
            if (this.clientMarkers.has(client.id)) {
                continue;
            }
            const marker = new this.google.Marker({
                map: this.liveMap,
                position: { lat: client.lat, lng: client.lng },
                title: client.name,
                zIndex: 1,
                icon: {
                    path: this.google.core.SymbolPath.CIRCLE,
                    scale: 6,
                    fillColor: "#7C5CFC",
                    fillOpacity: 1,
                    strokeColor: "#FFFFFF",
                    strokeWeight: 2,
                },
            });
            marker.addListener("click", () => {
                this.liveInfo.setContent(
                    `<strong>${client.name}</strong><div class="text-muted">${client.category || "Customer"}</div>`
                );
                this.liveInfo.open({ map: this.liveMap, anchor: marker });
            });
            this.clientMarkers.set(client.id, marker);
        }
        for (const [id, marker] of this.clientMarkers) {
            if (!shown.has(id)) {
                marker.setMap(null);
                this.clientMarkers.delete(id);
            }
        }
    }

    toggleSidebar() {
        this.state.collapsed = !this.state.collapsed;
    }

    // -- helpers used by the template -------------------------------------
    ago(iso) {
        return ago(iso);
    }

    clock(iso) {
        return iso ? new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }) : "";
    }

    money(value) {
        const currency = this.state.data ? this.state.data.currency : "";
        return `${currency}${(value || 0).toLocaleString(undefined, { maximumFractionDigits: 0 })}`;
    }

    number(value) {
        return (value || 0).toLocaleString();
    }

    get people() {
        const term = this.state.search.trim().toLowerCase();
        const people = this.state.data ? this.state.data.people : [];
        if (!term) {
            return people;
        }
        return people.filter(
            (person) =>
                (person.name || "").toLowerCase().includes(term) ||
                (person.code || "").toLowerCase().includes(term) ||
                (person.team || "").toLowerCase().includes(term)
        );
    }

    onSearch(ev) {
        this.state.search = ev.target.value;
    }

    /** Half-doughnut: the share punched in, drawn as an arc. */
    get gaugeArc() {
        const realtime = this.state.data.realtime;
        const total = realtime.total || 1;
        const share = realtime.punched_in / total;
        const radius = 70;
        const circumference = Math.PI * radius;
        return {
            length: circumference,
            filled: circumference * share,
            percent: Math.round(share * 100),
        };
    }

    /** Bars for the working-hours chart, scaled to the tallest day. */
    get hourBars() {
        const rows = this.state.data.working_hours || [];
        const max = Math.max(8, ...rows.map((row) => row.hours));
        return rows.map((row) => ({ ...row, height: Math.round((row.hours / max) * 100) }));
    }

    /** The four small counters, in the order the field cares about. */
    get counterCards() {
        const counters = this.state.data.counters;
        const meta = {
            visits: { label: "Visits Today", icon: "fa-map-marker", color: "#1a56db" },
            orders: { label: "Orders Submitted", icon: "fa-shopping-cart", color: "#14d3c0" },
            new_clients: { label: "New Customers", icon: "fa-user-plus", color: "#7c5cfc" },
            forms: { label: "Forms Filled", icon: "fa-file-text-o", color: "#1e90ff" },
            photos: { label: "Photos Uploaded", icon: "fa-camera", color: "#f59e0b" },
        };
        return Object.keys(meta)
            .filter((key) => counters[key])
            .map((key) => ({ key, ...meta[key], ...counters[key] }));
    }

    get visitShare() {
        const visits = this.state.data.visits;
        const total = visits.total || 1;
        return {
            done: Math.round((visits.done / total) * 100),
            ongoing: Math.round((visits.ongoing / total) * 100),
            planned: Math.round((visits.planned / total) * 100),
            missed: Math.round((visits.missed / total) * 100),
        };
    }

    /** A pie needs slices; build them as stroke-dasharray offsets on one circle. */
    expenseSlices() {
        const expenses = this.state.data.expenses;
        if (!expenses || !expenses.total) {
            return [];
        }
        const parts = [
            { key: "approved", label: "Approved", color: "#16A34A", amount: expenses.approved.amount },
            { key: "submitted", label: "Pending", color: "#F59E0B", amount: expenses.submitted.amount },
            { key: "draft", label: "Draft", color: "#1A56DB", amount: expenses.draft.amount },
            { key: "rejected", label: "Rejected", color: "#DC2626", amount: expenses.rejected.amount },
        ].filter((part) => part.amount > 0);
        const circumference = 2 * Math.PI * 42;
        let offset = 0;
        return parts.map((part) => {
            const share = part.amount / expenses.total;
            const slice = {
                ...part,
                dash: `${circumference * share} ${circumference}`,
                offset: -offset,
                percent: Math.round(share * 100),
            };
            offset += circumference * share;
            return slice;
        });
    }


    // -- Timeline ---------------------------------------------------------
    async openLiveView(view) {
        this.state.liveView = view;
        if (view === "timeline") {
            if (!this.state.timelineEmployees.length) {
                this.state.timelineEmployees = await this.orm.call(
                    "ff.dashboard",
                    "ff_timeline_employees",
                    []
                );
            }
            if (!this.state.timelineEmployeeId && this.state.timelineEmployees.length) {
                const open = this.state.openId;
                const known = this.state.timelineEmployees.find((row) => row.id === open);
                this.state.timelineEmployeeId = known ? known.id : this.state.timelineEmployees[0].id;
            }
            if (!this.state.timelineDate) {
                this.state.timelineDate = this.today();
            }
            await this.loadTimeline();
        } else {
            this.stopPlay();
            this.liveMap = null;   // the canvas is swapped; build it again
            this.markers.clear();
            this.clientMarkers.clear();
            await this.loadLive();
        }
    }

    today() {
        const now = new Date();
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(
            now.getDate()
        ).padStart(2, "0")}`;
    }

    onTimelineEmployee(ev) {
        this.state.timelineEmployeeId = parseInt(ev.target.value, 10);
    }

    onTimelineDate(ev) {
        this.state.timelineDate = ev.target.value;
    }

    async shiftDay(days) {
        const current = new Date(`${this.state.timelineDate}T00:00:00`);
        current.setDate(current.getDate() + days);
        if (current > new Date()) {
            return;
        }
        this.state.timelineDate = `${current.getFullYear()}-${String(current.getMonth() + 1).padStart(
            2,
            "0"
        )}-${String(current.getDate()).padStart(2, "0")}`;
        await this.loadTimeline();
    }

    async loadTimeline() {
        if (!this.state.timelineEmployeeId) {
            return;
        }
        this.stopPlay();
        this.state.timelineLoading = true;
        this.state.timeline = await this.orm.call("ff.dashboard", "ff_employee_timeline", [
            this.state.timelineEmployeeId,
            this.state.timelineDate,
        ]);
        this.state.timelineLoading = false;
        this.timelineFitted = false;
        await this.drawTimeline();
    }

    async drawTimeline() {
        const live = this.state.live;
        const key = live ? live.google_maps_key : "";
        if (!key || !this.state.timeline) {
            return;
        }
        if (!this.google) {
            try {
                this.google = await loadGoogleMaps(key);
                this.state.liveError = "";
            } catch (error) {
                this.state.liveError = error.message || String(error);
                return;
            }
        }
        if (!this.mapRef.el) {
            return;
        }
        if (!this.liveMap) {
            this.state.usage = await this.orm.call("ff.map.usage", "ff_record_web_map", []);
            this.liveMap = new this.google.Map(this.mapRef.el, {
                center: { lat: 20.5937, lng: 78.9629 },
                zoom: 5,
                mapTypeControl: true,
                streetViewControl: false,
                clickableIcons: false,
            });
            this.liveInfo = new this.google.InfoWindow();
        }
        this.paintTimeline();
    }

    paintTimeline() {
        const timeline = this.state.timeline;
        const path = (timeline.path || []).map((point) => ({ lat: point.lat, lng: point.lng }));

        // The travelled line, casing under colour, the way navigation apps draw it.
        for (const line of this.lines || []) {
            line.setMap(null);
        }
        this.lines = [];
        if (path.length > 1) {
            this.lines.push(
                new this.google.Polyline({
                    map: this.liveMap,
                    path,
                    strokeColor: "#FFFFFF",
                    strokeOpacity: 0.9,
                    strokeWeight: 9,
                }),
                new this.google.Polyline({
                    map: this.liveMap,
                    path,
                    strokeColor: "#16A34A",
                    strokeOpacity: 1,
                    strokeWeight: 5,
                })
            );
        }

        // Numbered stops.
        for (const marker of this.markers.values()) {
            marker.setMap(null);
        }
        this.markers.clear();
        const bounds = new this.google.core.LatLngBounds();
        let number = 0;
        for (const event of timeline.events) {
            if (!event.lat || !event.lng) {
                continue;
            }
            number++;
            const marker = new this.google.Marker({
                map: this.liveMap,
                position: { lat: event.lat, lng: event.lng },
                title: event.title,
                label: { text: String(number), color: "#fff", fontSize: "12px", fontWeight: "700" },
                icon: pinIcon(this.eventColor(event.kind), this.google.core),
            });
            marker.addListener("click", () => {
                this.liveInfo.setContent(
                    `<strong>${event.title}</strong><div class="text-muted">${this.clock(event.at)}</div>`
                );
                this.liveInfo.open({ map: this.liveMap, anchor: marker });
            });
            this.markers.set(`e${number}`, marker);
            bounds.extend({ lat: event.lat, lng: event.lng });
        }
        for (const point of path) {
            bounds.extend(point);
        }
        if ((number || path.length) && !this.timelineFitted) {
            this.timelineFitted = true;
            this.liveMap.fitBounds(bounds, 60);
        }
    }

    eventColor(kind) {
        return (
            {
                punch_in: "#16A34A",
                punch_out: "#DC2626",
                visit: "#1A56DB",
                order: "#14D3C0",
                form: "#1E90FF",
                expense: "#F59E0B",
                collection: "#7C5CFC",
                travel: "#94A3B8",
            }[kind] || "#94A3B8"
        );
    }

    eventIcon(kind) {
        return (
            {
                punch_in: "fa-sign-in",
                punch_out: "fa-sign-out",
                visit: "fa-map-marker",
                order: "fa-shopping-cart",
                form: "fa-file-text-o",
                expense: "fa-credit-card",
                collection: "fa-money",
                travel: "fa-motorcycle",
            }[kind] || "fa-circle"
        );
    }

    // -- play the day back -------------------------------------------------
    togglePlay() {
        if (this.state.playing) {
            this.stopPlay();
            return;
        }
        const path = this.state.timeline ? this.state.timeline.path : [];
        if (path.length < 2) {
            return;
        }
        this.state.playing = true;
        if (this.state.playIndex >= path.length - 1) {
            this.state.playIndex = 0;
        }
        if (!this.playMarker) {
            this.playMarker = new this.google.Marker({
                map: this.liveMap,
                zIndex: 99,
                icon: {
                    path: this.google.core.SymbolPath.FORWARD_CLOSED_ARROW,
                    scale: 5,
                    fillColor: "#1A56DB",
                    fillOpacity: 1,
                    strokeColor: "#FFFFFF",
                    strokeWeight: 2,
                },
            });
        }
        this.playMarker.setMap(this.liveMap);
        this.playTimer = setInterval(() => this.stepPlay(), 120);
    }

    stepPlay() {
        const path = this.state.timeline.path;
        const index = this.state.playIndex;
        if (index >= path.length - 1) {
            this.stopPlay();
            return;
        }
        const point = path[index];
        const next = path[index + 1];
        this.playMarker.setPosition({ lat: point.lat, lng: point.lng });
        // Point the arrow the way the journey goes.
        const heading =
            (Math.atan2(next.lng - point.lng, next.lat - point.lat) * 180) / Math.PI;
        const icon = this.playMarker.getIcon();
        this.playMarker.setIcon({ ...icon, rotation: heading });
        this.liveMap.panTo({ lat: point.lat, lng: point.lng });
        this.state.playIndex = index + 1;
    }

    stopPlay() {
        clearInterval(this.playTimer);
        this.playTimer = null;
        this.state.playing = false;
    }

    get playPercent() {
        const path = this.state.timeline ? this.state.timeline.path : [];
        return path.length > 1 ? Math.round((this.state.playIndex / (path.length - 1)) * 100) : 0;
    }

    get playClock() {
        const path = this.state.timeline ? this.state.timeline.path : [];
        const point = path[Math.min(this.state.playIndex, path.length - 1)];
        return point ? this.clock(point.at) : "";
    }

    // -- links into the rest of Odoo ---------------------------------------
    openLiveMap() {
        this.action.doAction({ type: "ir.actions.client", tag: "ff_live_map", name: "Live Map" });
    }

    /** The GPS trail of this person for today. */
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

    openEmployee(person) {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: person.name,
            res_model: "hr.employee",
            res_id: person.id,
            views: [[false, "form"]],
        });
    }

    openModel(model, name, domain, views) {
        this.action.doAction({
            type: "ir.actions.act_window",
            name,
            res_model: model,
            domain: domain || [],
            views: views || [
                [false, "list"],
                [false, "form"],
            ],
        });
    }
}

registry.category("actions").add("ff_panel", AixoloPanel);
