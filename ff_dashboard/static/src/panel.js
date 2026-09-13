/** @odoo-module **/

import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { Component, onWillStart, onWillUnmount, useRef, useState } from "@odoo/owl";
import { loadGoogleMaps, pinIcon } from "@ff_live_map/google";
import { FfChart } from "./chart";

const REFRESH_MS = 60000;

/** The sidebar. More entries land here as each area of the panel is built. */
const SECTIONS = [
    { key: "dashboard", label: "Dashboard", icon: "fa-th-large" },
    { key: "live", label: "Live Location", icon: "fa-map-marker" },
    { key: "people", label: "Employees", icon: "fa-users" },
    { key: "attendance", label: "Attendance", icon: "fa-calendar-check-o" },
    { key: "leaves", label: "Leaves", icon: "fa-plane" },
    { key: "expenses", label: "Expenses", icon: "fa-credit-card" },
    { key: "orders", label: "Orders", icon: "fa-shopping-cart" },
    { key: "visits", label: "Visits", icon: "fa-map-signs" },
    { key: "demands", label: "Demands", icon: "fa-shopping-basket" },
    { key: "collections", label: "Collections", icon: "fa-money" },
];

/** Which model method feeds each report section. */
const REPORTS = {
    attendance: "ff_attendance_report",
    leaves: "ff_leaves_report",
    expenses: "ff_expense_report",
    orders: "ff_order_report",
    visits: "ff_visit_report",
    demands: "ff_demand_section_report",
    collections: "ff_collection_report",
};

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
    static components = { FfChart };
    static props = {};

    setup() {
        this.orm = useService("orm");
        this.action = useService("action");
        this.notification = useService("notification");
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
            peopleView: "cards",
            org: null,
            orgSearch: "",
            collapsedNodes: [],
            report: null,
            reportLoading: false,
            exporting: false,
            options: null,
            filters: { employee_id: null, department_id: null, team_id: null,
                       date_from: null, date_to: null },
            calendar: null,
            calendarMonth: null,
            attendanceView: "summary",
            openDay: null,
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
        await this.loadOptions();
        this.state.data = await this.orm.call("ff.dashboard", "ff_dashboard_data", [
            this.state.period,
            this.activeFilters,
        ]);
        this.state.loading = false;
        this.state.updatedAt = new Date().toLocaleTimeString();
        if (this.state.section === "live") {
            await this.loadLive();
        }
    }

    async setPeriod(period) {
        this.state.period = period;
        if (REPORTS[this.state.section]) {
            await this.loadReport();
            return;
        }
        await this.load();
    }

    async openSection(key) {
        this.state.section = key;
        if (key === "live") {
            await this.loadLive();
        } else if (key === "people") {
            await this.loadPeople();
        } else if (REPORTS[key]) {
            // Each section reads different keys; keeping the previous payload
            // on screen while the new one loads breaks its template.
            this.state.report = null;
            this.state.openDay = null;
            await this.loadReport();
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

    // -- filters shared by every report ------------------------------------
    async loadOptions() {
        if (!this.state.options) {
            this.state.options = await this.orm.call("ff.dashboard", "ff_filter_options", []);
        }
    }

    get activeFilters() {
        const filters = {};
        for (const [key, value] of Object.entries(this.state.filters)) {
            if (value) {
                filters[key] = value;
            }
        }
        return filters;
    }

    get filterCount() {
        return Object.keys(this.activeFilters).length;
    }

    async setFilter(key, ev) {
        const value = parseInt(ev.target.value, 10);
        this.state.filters[key] = Number.isNaN(value) ? null : value;
        await this.refreshSection();
    }

    async clearFilters() {
        this.state.filters = { employee_id: null, department_id: null, team_id: null,
                               date_from: null, date_to: null };
        this.state.period = "month";
        await this.refreshSection();
    }

    // -- the date range ----------------------------------------------------
    /** The quick spans, beyond the three on the segmented control. */
    get periodChoices() {
        return [
            { key: "today", label: "Today" },
            { key: "yesterday", label: "Yesterday" },
            { key: "week", label: "This week" },
            { key: "last_week", label: "Last week" },
            { key: "month", label: "This month" },
            { key: "last_month", label: "Last month" },
            { key: "quarter", label: "This quarter" },
            { key: "year", label: "This year" },
            { key: "custom", label: "Custom dates" },
        ];
    }

    async choosePeriod(ev) {
        const period = ev.target.value;
        this.state.period = period;
        if (period !== "custom") {
            this.state.filters.date_from = null;
            this.state.filters.date_to = null;
        } else if (!this.state.filters.date_from) {
            // Open the custom range on the month being shown.
            const today = new Date();
            this.state.filters.date_from = this.dateString(new Date(today.getFullYear(), today.getMonth(), 1));
            this.state.filters.date_to = this.dateString(today);
        }
        await this.refreshSection();
    }

    async setDate(which, ev) {
        this.state.filters[which] = ev.target.value || null;
        this.state.period = "custom";
        if (this.state.filters.date_from && this.state.filters.date_to) {
            await this.refreshSection();
        }
    }

    dateString(date) {
        return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(
            date.getDate()
        ).padStart(2, "0")}`;
    }

    async refreshSection() {
        if (REPORTS[this.state.section]) {
            await this.loadReport();
            if (this.state.section === "attendance" && this.state.attendanceView === "calendar") {
                await this.loadCalendar();
            }
        }
    }

    // -- the attendance calendar -------------------------------------------
    async setAttendanceView(view) {
        this.state.attendanceView = view;
        if (view === "calendar") {
            await this.loadCalendar();
        }
    }

    async loadCalendar() {
        this.state.calendar = await this.orm.call("ff.dashboard", "ff_attendance_calendar", [
            this.state.calendarMonth,
            this.activeFilters,
        ]);
        this.state.calendarMonth = this.state.calendar.month;
    }

    async shiftMonth(delta) {
        const current = new Date(`${this.state.calendarMonth || this.state.calendar.month}T00:00:00`);
        current.setMonth(current.getMonth() + delta);
        if (current > new Date()) {
            return;  // a month that has not happened has nothing to show
        }
        this.state.calendarMonth = this.monthString(current);
        await this.loadCalendar();
    }

    /** Jump straight to a month from the picker. */
    async pickMonth(ev) {
        if (!ev.target.value) {
            return;
        }
        this.state.calendarMonth = `${ev.target.value}-01`;
        await this.loadCalendar();
    }

    async thisMonth() {
        this.state.calendarMonth = this.monthString(new Date());
        await this.loadCalendar();
    }

    monthString(date) {
        return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-01`;
    }

    get isCurrentMonth() {
        const shown = this.state.calendar ? this.state.calendar.month.slice(0, 7) : "";
        return shown === this.monthString(new Date()).slice(0, 7);
    }

    openDayDetail(cell) {
        this.state.openDay = this.state.openDay && this.state.openDay.date === cell.date ? null : cell;
    }

    /** A day shows a handful of boxes however big the team is. */
    visibleBoxes(cell) {
        return cell.boxes.slice(0, 16);
    }

    hiddenBoxes(cell) {
        return Math.max(cell.boxes.length - 16, 0);
    }

    /** The people to name in the hover card, worst news first. */
    popPeople(cell) {
        const order = { absent: 0, late: 1, leave: 2, present: 3, future: 4 };
        return [...cell.boxes].sort((a, b) => order[a.status] - order[b.status]).slice(0, 6);
    }

    boxClass(status) {
        return {
            present: "ff_box_present",
            late: "ff_box_late",
            absent: "ff_box_absent",
            leave: "ff_box_leave",
            future: "ff_box_future",
        }[status];
    }

    /** How full the day looks at a glance, for the tint behind the boxes. */
    dayFill(cell) {
        const total = cell.boxes.length || 1;
        return Math.round((cell.present / total) * 100);
    }

    // -- drill into the Odoo records behind a section ----------------------
    get reportEmployeeIds() {
        return this.state.report ? this.state.report.employee_ids : [];
    }

    /** The period of the report, as a domain leaf on a date field. */
    periodLeaf(field) {
        const start = this.state.report ? this.state.report.start : null;
        return start ? [[field, ">=", start]] : [];
    }

    drillAttendance(extra) {
        this.openModel(
            "hr.attendance",
            "Attendance",
            [["employee_id", "in", this.reportEmployeeIds]]
                .concat(this.periodLeaf("check_in"))
                .concat(extra || []),
            [
                [false, "list"],
                [false, "form"],
            ]
        );
    }

    drillLeaves(extra) {
        this.openModel("hr.leave", "Time Off", [["employee_id", "in", this.reportEmployeeIds]].concat(extra || []));
    }

    drillExpenses(extra) {
        this.openModel(
            "ff.expense.claim",
            "Expense Claims",
            [["employee_id", "in", this.reportEmployeeIds]].concat(this.periodLeaf("date")).concat(extra || [])
        );
    }

    drillOrders(extra) {
        const demand = this.state.report && this.state.report.flow === "demand";
        const model = demand ? "ff.demand" : "sale.order";
        const employeeField = demand ? "employee_id" : "ff_employee_id";
        const dateField = demand ? "date" : "date_order";
        this.openModel(
            model,
            demand ? "Outlet Demands" : "Orders",
            [[employeeField, "in", this.reportEmployeeIds]].concat(this.periodLeaf(dateField)).concat(extra || [])
        );
    }

    /** Records behind a generic section, narrowed by a tile's own domain. */
    drillGeneric(extra) {
        const report = this.state.report;
        if (!report || !report.model) {
            return;
        }
        const label = this.sections.find((s) => s.key === this.state.section).label;
        this.openModel(
            report.model,
            label,
            [[report.employee_field, "in", report.employee_ids]]
                .concat(this.periodLeaf(report.date_field))
                .concat(extra || [])
        );
    }

    openGenericRow(row) {
        const report = this.state.report;
        this.openModel(report.model, this.sections.find((s) => s.key === this.state.section).label, [
            ["id", "=", row.id],
        ]);
    }

    genericChart(chart) {
        return { labels: chart.labels, datasets: [{ label: chart.title, data: chart.values }] };
    }

    cell(column, row) {
        const value = row[column.key];
        if (column.money) {
            return this.money(value);
        }
        return value === null || value === undefined || value === "" ? "–" : value;
    }

    /** The section, as an Excel file with the same period and filters. */
    async exportSection() {
        this.state.exporting = true;
        try {
            const url = await this.orm.call("ff.dashboard", "ff_panel_export", [
                this.state.section,
                this.state.period,
                this.activeFilters,
            ]);
            if (url) {
                window.location.href = url;
            } else {
                this.notification.add("Nothing to export for this section.", { type: "warning" });
            }
        } finally {
            this.state.exporting = false;
        }
    }

    // -- the report sections ----------------------------------------------
    async loadReport() {
        const method = REPORTS[this.state.section];
        if (!method) {
            return;
        }
        this.state.reportLoading = true;
        await this.loadOptions();
        this.state.report = await this.orm.call("ff.dashboard", method, [
            this.state.period,
            this.activeFilters,
        ]);
        this.state.reportLoading = false;
    }

    // -- what the charts are drawn from ------------------------------------
    chartLabels(series) {
        return (series || []).map((row) => row.label);
    }

    chartValues(series, key) {
        return (series || []).map((row) => row[key] || 0);
    }

    /** Horizontal bars for a "top ten" list. */
    topChart(rows, key) {
        return {
            labels: (rows || []).map((row) => row.name),
            datasets: [
                {
                    label: key === "quantity" ? "Units" : key === "days" ? "Days" : "Amount",
                    data: (rows || []).map((row) => row[key] || 0),
                },
            ],
        };
    }

    stateBadge(state) {
        return (
            {
                draft: "ff_pill_grey",
                submitted: "ff_pill_blue",
                confirm: "ff_pill_amber",
                validate1: "ff_pill_amber",
                validate: "ff_pill_green",
                approved: "ff_pill_green",
                sale: "ff_pill_green",
                supplied: "ff_pill_green",
                quoted: "ff_pill_blue",
                partial: "ff_pill_amber",
                refuse: "ff_pill_red",
                rejected: "ff_pill_red",
                cancel: "ff_pill_red",
                cancelled: "ff_pill_red",
                onsite: "ff_pill_green",
                offsite: "ff_pill_red",
                collected: "ff_pill_amber",
                received: "ff_pill_green",
                in_progress: "ff_pill_blue",
                done: "ff_pill_green",
                todo: "ff_pill_grey",
            }[state] || "ff_pill_grey"
        );
    }

    stateWord(state) {
        return (
            {
                confirm: "To approve",
                validate1: "Second approval",
                validate: "Approved",
                refuse: "Refused",
                sale: "Confirmed",
                draft: "Draft",
                submitted: "Submitted",
                approved: "Approved",
                rejected: "Rejected",
                quoted: "Quoted",
                partial: "Partly quoted",
                supplied: "Supplied",
                cancelled: "Cancelled",
                cancel: "Cancelled",
                onsite: "Onsite",
                offsite: "Offsite",
                collected: "With employee",
                received: "Received",
                in_progress: "In progress",
                done: "Done",
                todo: "To do",
            }[state] || state
        );
    }

    // -- Employees: cards and hierarchy ------------------------------------
    async loadPeople() {
        if (!this.state.live) {
            this.state.live = await this.orm.call("ff.employee.status", "ff_live_map", [false]);
        }
        if (this.state.peopleView === "org" && !this.state.org) {
            this.state.org = await this.orm.call("ff.dashboard", "ff_org_tree", []);
        }
    }

    async setPeopleView(view) {
        this.state.peopleView = view;
        await this.loadPeople();
    }

    onOrgSearch(ev) {
        this.state.orgSearch = ev.target.value;
    }

    /** Collapsing is remembered per person, so a big tree stays readable. */
    toggleNode(node) {
        const open = this.state.collapsedNodes;
        const at = open.indexOf(node.id);
        if (at === -1) {
            open.push(node.id);
        } else {
            open.splice(at, 1);
        }
    }

    isCollapsed(node) {
        return this.state.collapsedNodes.includes(node.id);
    }

    expandAll() {
        this.state.collapsedNodes = [];
    }

    collapseAll() {
        const ids = [];
        const walk = (nodes) => {
            for (const node of nodes) {
                if (node.children.length) {
                    ids.push(node.id);
                    walk(node.children);
                }
            }
        };
        walk(this.state.org ? this.state.org.roots : []);
        this.state.collapsedNodes = ids;
    }

    /** A search hides the branches that do not match, without losing the shape. */
    matchesOrg(node) {
        const term = this.state.orgSearch.trim().toLowerCase();
        if (!term) {
            return true;
        }
        const hit =
            (node.name || "").toLowerCase().includes(term) ||
            (node.job || "").toLowerCase().includes(term) ||
            (node.team || "").toLowerCase().includes(term) ||
            (node.code || "").toLowerCase().includes(term);
        return hit || node.children.some((child) => this.matchesOrg(child));
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
