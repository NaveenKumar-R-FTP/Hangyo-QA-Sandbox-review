/**
 * performanceDashboard - Performance Dashboard (new component, Performance Dashboard project).
 * Loads three live calls in parallel: summary (cards 1-4, 6, 8, 9), freezer (card 5), region (card 7).
 */
import { LightningElement } from 'lwc';
import getSummary from '@salesforce/apex/PerformanceDashboardController.getSummary';
import getFreezer from '@salesforce/apex/PerformanceDashboardController.getFreezer';
import getRegion from '@salesforce/apex/PerformanceDashboardController.getRegion';

const RUPEE = '\u20B9';
const DASH = '\u2014';
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function n(v) { return (v === null || v === undefined) ? 0 : Number(v); }

/** Indian money format: 12,345 | 12.3 L | 1.23 Cr */
function inr(v) {
    const x = n(v);
    const a = Math.abs(x);
    if (a >= 10000000) return RUPEE + (x / 10000000).toFixed(2) + ' Cr';
    if (a >= 100000) return RUPEE + (x / 100000).toFixed(1) + ' L';
    return RUPEE + Math.round(x).toLocaleString('en-IN');
}
function count(v) { return Math.round(n(v)).toLocaleString('en-IN'); }
function pctText(v) { return n(v).toFixed(n(v) % 1 === 0 ? 0 : 1) + '%'; }

function tier(p) {
    const x = n(p);
    if (x >= 100) return { cls: 'tier-green', label: 'Achieved' };
    if (x >= 90) return { cls: 'tier-teal', label: 'On track' };
    if (x >= 70) return { cls: 'tier-amber', label: 'Behind' };
    return { cls: 'tier-red', label: 'Critical' };
}
function growth(g) {
    if (g === null || g === undefined) return { text: DASH, cls: 'value muted' };
    const x = Number(g);
    return { text: (x >= 0 ? '\u25B2 ' : '\u25BC ') + Math.abs(x).toFixed(1) + '%', cls: x >= 0 ? 'value up' : 'value down' };
}
function bar(p) { return 'width:' + Math.max(0, Math.min(n(p), 100)) + '%'; }
function fmtDate(d) {
    if (!d) return '';
    const p = String(d).split('-');
    return Number(p[2]) + ' ' + MONTHS[Number(p[1]) - 1] + ' ' + p[0];
}
function errText(e) {
    if (e && e.body && e.body.message) return e.body.message;
    if (e && e.message) return e.message;
    return 'Something went wrong. Please refresh.';
}

export default class PerformanceDashboard extends LightningElement {
    mode = 'MTD';
    summary;
    freezer;
    region;
    loadingSummary = true;
    loadingFreezer = true;
    loadingRegion = true;
    errorSummary;
    errorFreezer;
    errorRegion;
    openHub;

    connectedCallback() {
        this.load();
    }

    load() {
        const mode = this.mode;
        this.loadingSummary = true;
        this.loadingFreezer = true;
        this.loadingRegion = true;
        this.errorSummary = undefined;
        this.errorFreezer = undefined;
        this.errorRegion = undefined;

        getSummary({ mode })
            .then((r) => { if (mode === this.mode) this.summary = r; })
            .catch((e) => { if (mode === this.mode) this.errorSummary = errText(e); })
            .finally(() => { if (mode === this.mode) this.loadingSummary = false; });
        getFreezer({ mode })
            .then((r) => { if (mode === this.mode) this.freezer = r; })
            .catch((e) => { if (mode === this.mode) this.errorFreezer = errText(e); })
            .finally(() => { if (mode === this.mode) this.loadingFreezer = false; });
        getRegion({ mode })
            .then((r) => { if (mode === this.mode) this.region = r; })
            .catch((e) => { if (mode === this.mode) this.errorRegion = errText(e); })
            .finally(() => { if (mode === this.mode) this.loadingRegion = false; });
    }

    handleMtd() { if (this.mode !== 'MTD') { this.mode = 'MTD'; this.load(); } }
    handleYtd() { if (this.mode !== 'YTD') { this.mode = 'YTD'; this.load(); } }
    handleRefresh() { this.load(); }
    handleHub(event) {
        const key = event.currentTarget.dataset.hub;
        this.openHub = (this.openHub === key) ? null : key;
    }

    // ---------------------------------------------------------------- state
    get isMtd() { return this.mode === 'MTD'; }
    get mtdClass() { return this.isMtd ? 'toggle active' : 'toggle'; }
    get ytdClass() { return this.isMtd ? 'toggle' : 'toggle active'; }
    get accessDenied() { return !!(this.summary && this.summary.accessDenied); }
    get ready() { return !!(this.summary && !this.summary.accessDenied); }
    get showAttendance() { return this.ready && !!this.summary.attendance; }
    get showToday() { return this.ready && !!this.summary.today; }

    // ---------------------------------------------------------------- card 1
    get title() {
        const h = this.summary && this.summary.header;
        if (!h) return 'Performance';
        return (h.division || '') + (h.division && h.designation ? ' - ' : '') + (h.designation || '');
    }
    get userName() { return this.summary && this.summary.header ? this.summary.header.userName : ''; }
    get directReports() { return this.summary && this.summary.header ? count(this.summary.header.directReports) : '0'; }
    get periodLabel() {
        if (!this.summary || !this.summary.periodStart) return '';
        return fmtDate(this.summary.periodStart) + ' - ' + fmtDate(this.summary.periodEnd);
    }
    get asOfLabel() {
        if (!this.summary || !this.summary.asOf) return '';
        const d = new Date(this.summary.asOf);
        return 'As of ' + d.toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
    }

    // ---------------------------------------------------------------- card 2
    get target() {
        const t = this.summary && this.summary.target;
        if (!t) return null;
        const tr = tier(t.percent);
        const left = n(t.remainingDays);
        return {
            achievement: inr(t.achievement),
            target: inr(t.target),
            percent: pctText(t.percent),
            tierLabel: tr.label,
            tierClass: 'tier-text ' + tr.cls,
            barClass: 'bar-fill ' + tr.cls,
            barStyle: bar(t.percent),
            balance: inr(t.balance),
            rrr: inr(t.rrr) + '/day',
            daysLeft: left + (left === 1 ? ' day left' : ' days left') + (this.isMtd ? ' in month' : ' to 31 Mar')
        };
    }

    // ---------------------------------------------------------------- cards 3, 4
    get calls() {
        const c = this.summary && this.summary.calls;
        if (!c) return null;
        return { tc: count(c.totalCalls), pc: count(c.productiveCalls), percent: pctText(c.percent) };
    }
    get growthCard() {
        const g = this.summary && this.summary.growth;
        if (!g) return null;
        const gr = growth(g.growthPercent);
        return { text: gr.text, cls: gr.cls, current: inr(g.current), lastYear: inr(g.lastYear) };
    }

    // ---------------------------------------------------------------- card 5
    get freezerCard() {
        const f = this.freezer;
        if (!f || f.accessDenied) return null;
        return {
            active: count(f.activeFreezers),
            billed: count(f.billedFreezers),
            billedPct: pctText(f.billedPercent),
            barStyle: bar(f.billedPercent),
            dfSale: inr(f.dfSale),
            perFreezer: inr(f.perFreezer)
        };
    }

    // ---------------------------------------------------------------- card 6
    get attendance() {
        const a = this.summary && this.summary.attendance;
        if (!a) return null;
        return {
            total: count(a.total), present: count(a.present), leave: count(a.leaveCount),
            absent: count(a.absent), notMarked: count(a.notMarked)
        };
    }

    // ---------------------------------------------------------------- card 9
    get today() {
        const t = this.summary && this.summary.today;
        if (!t) return null;
        return {
            orderValue: inr(t.orderValue), orderCount: count(t.orderCount) + (t.orderCount === 1 ? ' order' : ' orders'),
            tc: count(t.totalCalls), pc: count(t.productiveCalls), pcPercent: pctText(t.pcPercent),
            throughPut: inr(t.dfThroughPut)
        };
    }
    get todayLabel() {
        const d = new Date();
        return 'Today - ' + d.getDate() + ' ' + MONTHS[d.getMonth()];
    }

    // ---------------------------------------------------------------- card 8
    get primary() {
        const p = this.summary && this.summary.primary;
        if (!p) return null;
        const gr = growth(p.growthPercent);
        return { current: inr(p.current), lastYear: inr(p.lastYear), text: gr.text, cls: gr.cls };
    }

    // ---------------------------------------------------------------- card 7
    get hubs() {
        if (!this.region || this.region.accessDenied || !this.region.hubs) return [];
        return this.region.hubs.map((h) => {
            const tr = tier(h.percent);
            const open = this.openHub === h.hub;
            return {
                key: h.hub,
                name: h.hub,
                head: h.headName ? (h.headDesignation ? h.headDesignation + ' - ' : '') + h.headName : '',
                percent: pctText(h.percent),
                pctClass: 'hub-pct ' + tr.cls,
                barClass: 'bar-fill ' + tr.cls,
                barStyle: bar(h.percent),
                achievement: inr(h.achievement),
                target: inr(h.target),
                primary: inr(h.primarySale),
                isOpen: open,
                chevron: open ? '\u25BE' : '\u25B8',
                hasMembers: h.members && h.members.length > 0,
                members: (h.members || []).map((m) => {
                    const mt = tier(m.percent);
                    return {
                        key: m.userId,
                        name: m.name,
                        designation: m.designation || '',
                        achievement: inr(m.achievement),
                        target: inr(m.target),
                        percent: pctText(m.percent),
                        pctClass: 'member-pct ' + mt.cls
                    };
                })
            };
        });
    }
    get hasHubs() { return this.hubs.length > 0; }
}