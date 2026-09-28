/** @odoo-module **/

import { loadBundle } from "@web/core/assets";
import { Component, onWillStart, onMounted, onWillUnmount, onPatched, useRef } from "@odoo/owl";

/**
 * A chart, drawn with the Chart.js that Odoo already ships for its graph views.
 *
 * Hand-drawn bars cannot say what they are worth; a chart carries its own
 * tooltips, axes and legend. The component owns one canvas: it builds the chart
 * on mount, rebuilds it when the data changes, and destroys it on the way out
 * so nothing is left holding the canvas.
 */
export class FfChart extends Component {
    static template = "ff_dashboard.Chart";
    static props = {
        type: { type: String },
        labels: { type: Array },
        datasets: { type: Array },
        height: { type: Number, optional: true },
        money: { type: Boolean, optional: true },
        currency: { type: String, optional: true },
        stacked: { type: Boolean, optional: true },
        horizontal: { type: Boolean, optional: true },
        legend: { type: Boolean, optional: true },
    };

    setup() {
        this.canvas = useRef("canvas");
        onWillStart(() => loadBundle("web.chartjs_lib"));
        onMounted(() => this.render());
        onPatched(() => this.render());
        onWillUnmount(() => this.destroy());
    }

    get signature() {
        return JSON.stringify([this.props.labels, this.props.datasets]);
    }

    render() {
        if (!this.canvas.el || !window.Chart) {
            return;
        }
        // Rebuilding an unchanged chart would throw away its hover state.
        if (this.chart && this.lastSignature === this.signature) {
            return;
        }
        this.destroy();
        this.lastSignature = this.signature;
        this.chart = new window.Chart(this.canvas.el, {
            type: this.props.type,
            data: { labels: this.props.labels, datasets: this.props.datasets.map((set) => this.style(set)) },
            options: this.options(),
        });
    }

    style(dataset) {
        const colour = dataset.color || "#1a56db";
        if (this.props.type === "line") {
            return {
                ...dataset,
                borderColor: colour,
                backgroundColor: colour + "22",
                fill: true,
                tension: 0.35,
                pointRadius: 3,
                pointHoverRadius: 6,
                borderWidth: 2,
            };
        }
        if (["doughnut", "pie"].includes(this.props.type)) {
            return {
                ...dataset,
                backgroundColor: dataset.colors || ["#1a56db", "#16a34a", "#f59e0b", "#dc2626", "#7c5cfc", "#14d3c0"],
                borderWidth: 2,
                borderColor: "#fff",
                hoverOffset: 6,
            };
        }
        return {
            ...dataset,
            backgroundColor: dataset.colors || colour,
            hoverBackgroundColor: colour,
            borderRadius: 6,
            borderSkipped: false,
            maxBarThickness: 42,
        };
    }

    /** Format a value the way the card around it would. */
    format(value) {
        if (this.props.money) {
            return `${this.props.currency || ""}${Number(value).toLocaleString(undefined, {
                maximumFractionDigits: 2,
            })}`;
        }
        return Number(value).toLocaleString();
    }

    options() {
        const round = ["doughnut", "pie"].includes(this.props.type);
        const options = {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: round ? "nearest" : "index", intersect: false },
            plugins: {
                legend: {
                    display: this.props.legend !== false && (round || this.props.datasets.length > 1),
                    position: round ? "right" : "top",
                    labels: { boxWidth: 12, boxHeight: 12, usePointStyle: true, font: { size: 11 } },
                },
                tooltip: {
                    backgroundColor: "rgba(15, 27, 61, 0.92)",
                    padding: 10,
                    cornerRadius: 8,
                    titleFont: { size: 12, weight: "700" },
                    bodyFont: { size: 12 },
                    displayColors: true,
                    callbacks: {
                        label: (item) => {
                            const name = item.dataset.label ? `${item.dataset.label}: ` : "";
                            const value = round ? item.parsed : item.parsed.y ?? item.parsed;
                            return ` ${name}${this.format(value)}`;
                        },
                    },
                },
            },
        };
        if (!round) {
            options.indexAxis = this.props.horizontal ? "y" : "x";
            options.scales = {
                x: {
                    stacked: Boolean(this.props.stacked),
                    grid: { display: false },
                    ticks: { font: { size: 10 }, color: "#7385a8", maxRotation: 0, autoSkipPadding: 12 },
                },
                y: {
                    stacked: Boolean(this.props.stacked),
                    beginAtZero: true,
                    grid: { color: "#eef2fa" },
                    border: { display: false },
                    ticks: {
                        font: { size: 10 },
                        color: "#7385a8",
                        precision: 0,
                        callback: (value) => this.format(value),
                    },
                },
            };
        }
        return options;
    }

    destroy() {
        if (this.chart) {
            this.chart.destroy();
            this.chart = null;
        }
    }
}
