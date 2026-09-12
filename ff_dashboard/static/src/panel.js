/** @odoo-module **/

import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { Component, onWillStart, onWillUnmount, useState } from "@odoo/owl";

const REFRESH_MS = 60000;

/** The sidebar. More entries land here as each area of the panel is built. */
const SECTIONS = [
    { key: "dashboard", label: "Dashboard", icon: "fa-th-large" },
];

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
        this.state = useState({
            section: "dashboard",
            period: "month",
            search: "",
            data: null,
            loading: true,
            updatedAt: "",
            collapsed: false,
        });

        onWillStart(() => this.load());
        this.timer = setInterval(() => this.load(), REFRESH_MS);
        onWillUnmount(() => clearInterval(this.timer));
    }

    async load() {
        this.state.data = await this.orm.call("ff.dashboard", "ff_dashboard_data", [this.state.period]);
        this.state.loading = false;
        this.state.updatedAt = new Date().toLocaleTimeString();
    }

    async setPeriod(period) {
        this.state.period = period;
        await this.load();
    }

    openSection(key) {
        this.state.section = key;
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

    // -- links into the rest of Odoo ---------------------------------------
    openLiveMap() {
        this.action.doAction({ type: "ir.actions.client", tag: "ff_live_map", name: "Live Map" });
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
