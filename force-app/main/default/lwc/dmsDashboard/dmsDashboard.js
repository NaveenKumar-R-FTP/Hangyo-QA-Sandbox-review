/**
 * dmsDashboard.js  v3
 * Fixes: date window display, week date labels, category null,
 *        prev 30d box on all cards, announcement ticker
 */
import { LightningElement, wire, track } from 'lwc';
import { loadScript }                     from 'lightning/platformResourceLoader';
import chartjs                            from '@salesforce/resourceUrl/chartjs';
import getDashboardData                   from '@salesforce/apex/DmsDashboardController.getDashboardData';
import userId                             from '@salesforce/user/Id';
import { getRecord }                      from 'lightning/uiRecordApi';

const USER_FIELDS = ['User.AccountId', 'User.Name'];

const PIE_COLORS = [
    '#e8006a','#f472b6','#fb7185','#f97316',
    '#facc15','#4ade80','#60a5fa','#a78bfa',
    '#34d399','#f43f5e'
];

const C = {
    primary:   'rgba(232,0,106,0.9)',
    primaryBg: 'rgba(232,0,106,0.12)',
    accent:    'rgba(244,114,182,0.85)',
    accentBg:  'rgba(244,114,182,0.08)',
    grid:      'rgba(232,0,106,0.10)',
    text:      '#6b1a3a',
};

export default class DmsDashboard extends LightningElement {

    @track isLoading    = true;
    @track hasError     = false;
    @track errorMessage = '';
    @track isReady      = false;

    _distributorAccountId = null;
    _payload              = null;
    _chartjsLoaded        = false;
    _trendChart           = null;
    _categoryChart        = null;
    _chartsRendered       = false;

    @wire(getRecord, { recordId: userId, fields: USER_FIELDS })
    wiredUser({ error, data }) {
        if (data) {
            const accountId = data.fields.AccountId.value;
            if (accountId && accountId !== this._distributorAccountId) {
                this._distributorAccountId = accountId;
                this._loadAll();
            }
        } else if (error) {
            this._setError('Could not retrieve user account: ' + JSON.stringify(error));
        }
    }

    async _loadAll() {
        try {
            const [payload] = await Promise.all([
                getDashboardData({ distributorAccountId: this._distributorAccountId }),
                this._loadChartJs(),
            ]);
            this._payload = payload;
            this.isLoading = false;
            this.isReady   = true;
        } catch (err) {
            this._setError(err.body?.message || err.message || 'Unknown error');
        }
    }

    _loadChartJs() {
        if (this._chartjsLoaded) return Promise.resolve();
        return loadScript(this, chartjs).then(() => { this._chartjsLoaded = true; });
    }

    renderedCallback() {
        if (!this.isReady || !this._chartjsLoaded || !this._payload || this._chartsRendered) return;
        this._chartsRendered = true;
        this._renderTrendChart();
        this._renderCategoryChart();
    }

    // ── TREND CHART ───────────────────────────────────────────────────────────
    _renderTrendChart() {
        if (this._trendChart) { this._trendChart.destroy(); this._trendChart = null; }
        const canvas = this.refs.trendCanvas;
        if (!canvas) return;

        let buckets = [...(this._payload.weeklyTrend || [])];
        while (buckets.length < 4) {
            buckets = [{ weekLabel: '—', secondarySales: 0, primaryPurchase: 0 }, ...buckets];
        }

        const labels    = buckets.map(b => b.weekLabel);
        const secondary = buckets.map(b => Number(b.secondarySales)  || 0);
        const primary   = buckets.map(b => Number(b.primaryPurchase) || 0);

        this._trendChart = new window.Chart(canvas, {
            type: 'line',
            data: {
                labels,
                datasets: [
                    {
                        label: 'Secondary Sales',
                        data: secondary,
                        borderColor: '#e8006a',
                        backgroundColor: 'rgba(232,0,106,0.12)',
                        borderWidth: 3,
                        pointBackgroundColor: '#e8006a',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        pointRadius: 5,
                        pointHoverRadius: 8,
                        tension: 0.45,
                        fill: true,
                    },
                    {
                        label: 'Primary Purchase',
                        data: primary,
                        borderColor: '#f9a8d4',
                        backgroundColor: 'rgba(249,168,212,0.10)',
                        borderWidth: 3,
                        pointBackgroundColor: '#f9a8d4',
                        pointBorderColor: '#fff',
                        pointBorderWidth: 2,
                        pointRadius: 5,
                        pointHoverRadius: 8,
                        tension: 0.45,
                        fill: true,
                    },
                ],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        labels: {
                            color: '#6b1a3a',
                            font: { size: 11, weight: '600' },
                            usePointStyle: true,
                            pointStyle: 'circle',
                            pointStyleWidth: 10,
                            padding: 16,
                        }
                    },
                    tooltip: {
                        backgroundColor: '#fff',
                        titleColor: '#6b1a3a',
                        bodyColor: '#333',
                        borderColor: '#e8006a',
                        borderWidth: 1,
                        callbacks: { label: ctx => '  ₹' + fmtAmt(ctx.parsed.y) },
                    },
                },
                scales: {
                    x: {
                        grid: { color: 'rgba(232,0,106,0.10)' },
                        ticks: { color: '#6b1a3a', font: { size: 10 }, maxRotation: 20 }
                    },
                    y: {
                        grid: { color: 'rgba(232,0,106,0.10)' },
                        ticks: {
                            color: '#6b1a3a',
                            font: { size: 11 },
                            callback: v => '₹' + fmtAmt(v),
                        },
                    },
                },
            },
        });
    }

    // ── CATEGORY DOUGHNUT ─────────────────────────────────────────────────────
    _renderCategoryChart() {
        if (this._categoryChart) { this._categoryChart.destroy(); this._categoryChart = null; }
        const canvas = this.refs.categoryCanvas;
        if (!canvas) return;

        const cats   = (this._payload.categoryData || []).filter(c => Number(c.currentAmount) > 0);
        if (!cats.length) return;

        const labels = cats.map(c => c.category || 'Uncategorised');
        const values = cats.map(c => Number(c.currentAmount) || 0);
        const colors = cats.map((_, i) => PIE_COLORS[i % PIE_COLORS.length]);
        const total  = values.reduce((a, b) => a + b, 0);

        this._categoryChart = new window.Chart(canvas, {
            type: 'doughnut',
            data: {
                labels,
                datasets: [{
                    data: values,
                    backgroundColor: colors,
                    borderColor: '#fff',
                    borderWidth: 3,
                    hoverOffset: 12,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                cutout: '58%',
                plugins: {
                    legend: {
                        position: 'right',
                        labels: {
                            color: C.text,
                            font: { size: 10 },
                            usePointStyle: true,
                            pointStyleWidth: 10,
                            padding: 12,
                        },
                    },
                    tooltip: {
                        backgroundColor: '#fff',
                        titleColor: C.text,
                        bodyColor: '#333',
                        borderColor: '#e8006a',
                        borderWidth: 1,
                        callbacks: {
                            label: ctx => '  ₹' + fmtAmt(ctx.parsed) + '  (' + ((ctx.parsed / total) * 100).toFixed(1) + '%)',
                        },
                    },
                },
            },
        });
    }

    // ── Topbar ────────────────────────────────────────────────────────────────
    get distributorName()     { return this._payload?.distributorInfo?.name     || '—'; }
    get distributorLocation() { return this._payload?.distributorInfo?.location || '—'; }
    get isSuperStockist()     { return this._payload?.distributorInfo?.isSuperStockist; }
    get activeRetailersLabel(){ return this.isSuperStockist ? 'Active Distributors' : 'Active Retailers'; }
    get topRetailersLabel()   { return this.isSuperStockist ? 'Top 5 Under-SS Distributors' : 'Top 5 Retailers'; }
    get topRetailersColLabel(){ return this.isSuperStockist ? 'Distributor' : 'Retailer'; }
    get todayFormatted() {
        return new Date().toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' });
    }

    // ── Date window banners ───────────────────────────────────────────────────
    get currentWindow() { return this._payload?.currentWindowLabel || ''; }
    get prevWindow()    { return this._payload?.prevWindowLabel    || ''; }

    // ── Announcements ─────────────────────────────────────────────────────────
    get hasAnnouncements() { return (this._payload?.announcements?.length || 0) > 0; }
    get announcementMessages() { return (this._payload?.announcements || []).map(a => a.message); }

    // ── KPI ───────────────────────────────────────────────────────────────────
    get salesCurrentFormatted()  { return fmtINR(this._payload?.kpi?.salesCurrent); }
    get salesPrevFormatted()     { return fmtINR(this._payload?.kpi?.salesPrev); }
    get salesDelta()             { return deltaStr(this._payload?.kpi?.salesCurrent,   this._payload?.kpi?.salesPrev); }
    get salesDeltaClass()        { return deltaClass(this._payload?.kpi?.salesCurrent, this._payload?.kpi?.salesPrev, true); }

    get purchaseCurrentFormatted() { return fmtINR(this._payload?.kpi?.purchaseCurrent); }
    get purchasePrevFormatted()    { return fmtINR(this._payload?.kpi?.purchasePrev); }
    get purchaseDelta()            { return deltaStr(this._payload?.kpi?.purchaseCurrent,   this._payload?.kpi?.purchasePrev); }
    get purchaseDeltaClass()       { return deltaClass(this._payload?.kpi?.purchaseCurrent, this._payload?.kpi?.purchasePrev, true); }

    get returnsCurrentFormatted()  { return fmtINR(this._payload?.kpi?.returnsCurrent); }
    get returnsPrevFormatted()     { return fmtINR(this._payload?.kpi?.returnsPrev); }
    get returnsDelta()             { return deltaStr(this._payload?.kpi?.returnsCurrent,   this._payload?.kpi?.returnsPrev); }
    get returnsDeltaClass()        { return deltaClass(this._payload?.kpi?.returnsCurrent, this._payload?.kpi?.returnsPrev, false); }

    get activeRetailersCurrent() { return this._payload?.kpi?.activeRetailersCurrent ?? '—'; }
    get activeRetailersPrev()    { return this._payload?.kpi?.activeRetailersPrev    ?? '—'; }

    // ── Tables ────────────────────────────────────────────────────────────────
    get topRetailersRows() {
        return (this._payload?.topRetailers || []).map((r, i) => ({
            ...r, rank: i + 1,
            currentFmt: fmtINR(r.currentAmount),
            prevFmt:    fmtINR(r.prevAmount),
            delta:      deltaStr(r.currentAmount, r.prevAmount),
            deltaClass: deltaClass(r.currentAmount, r.prevAmount, true),
        }));
    }
    get topProductsRows() {
        return (this._payload?.topProducts || []).map((p, i) => ({
            ...p, rank: i + 1,
            currentFmt: fmtINR(p.currentAmount),
            prevFmt:    fmtINR(p.prevAmount),
            delta:      deltaStr(p.currentAmount, p.prevAmount),
            deltaClass: deltaClass(p.currentAmount, p.prevAmount, true),
        }));
    }

    _setError(msg) {
        this.isLoading = false; this.isReady = false;
        this.hasError = true; this.errorMessage = msg;
    }
    disconnectedCallback() {
        if (this._trendChart)    this._trendChart.destroy();
        if (this._categoryChart) this._categoryChart.destroy();
    }
}

function fmtAmt(v) {
    const n = Number(v) || 0;
    if (n >= 1e7) return (n/1e7).toFixed(2)+' Cr';
    if (n >= 1e5) return (n/1e5).toFixed(2)+' L';
    if (n >= 1e3) return (n/1e3).toFixed(1)+'K';
    return n.toFixed(0);
}
function fmtINR(v) { return '₹' + fmtAmt(Number(v)||0); }
function deltaStr(curr, prev) {
    curr = Number(curr)||0; prev = Number(prev)||0;
    if (prev === 0) return curr > 0 ? '+100%' : '—';
    const p = ((curr-prev)/prev)*100;
    return (p>=0?'+':'')+p.toFixed(1)+'%';
}
function deltaClass(curr, prev, higherIsBetter) {
    curr = Number(curr)||0; prev = Number(prev)||0;
    if (prev === 0) return curr > 0 ? (higherIsBetter ? 'kpi-delta-up' : 'kpi-delta-down') : 'kpi-delta-neutral';
    return (higherIsBetter ? curr>=prev : curr<=prev) ? 'kpi-delta-up' : 'kpi-delta-down';
}