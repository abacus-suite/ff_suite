/** @odoo-module **/

import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { Component, onWillStart, useState } from "@odoo/owl";

/** What Google has cost this month, and how much of the free tier is left. */
export class FieldForceMapCost extends Component {
    static template = "ff_live_map.MapCost";
    static props = {};

    setup() {
        this.orm = useService("orm");
        this.action = useService("action");
        this.state = useState({ summary: null, month: null });
        onWillStart(() => this.load());
    }

    async load() {
        this.state.summary = await this.orm.call("ff.map.usage", "ff_usage_summary", [this.state.month]);
    }

    /** Move the view one month back or forward. */
    async shiftMonth(delta) {
        const current = this.state.month ? new Date(`${this.state.month}-01`) : new Date();
        current.setMonth(current.getMonth() + delta);
        const now = new Date();
        if (current > now) {
            return;
        }
        const month = `${current.getFullYear()}-${String(current.getMonth() + 1).padStart(2, "0")}-01`;
        this.state.month = month;
        await this.load();
    }

    number(value) {
        return (value || 0).toLocaleString();
    }

    money(value) {
        return `${this.state.summary.currency}${(value || 0).toLocaleString(undefined, {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2,
        })}`;
    }

    barColor(percent) {
        if (percent >= 100) {
            return "bg-danger";
        }
        return percent >= 80 ? "bg-warning" : "bg-success";
    }

    openDetail(kind) {
        this.action.doAction({
            type: "ir.actions.act_window",
            name: "Map Requests",
            res_model: "ff.map.usage",
            views: [
                [false, "graph"],
                [false, "pivot"],
                [false, "list"],
            ],
            domain: kind ? [["kind", "=", kind]] : [],
            context: { search_default_this_month: 1, search_default_group_kind: 1 },
        });
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

registry.category("actions").add("ff_map_cost", FieldForceMapCost);
