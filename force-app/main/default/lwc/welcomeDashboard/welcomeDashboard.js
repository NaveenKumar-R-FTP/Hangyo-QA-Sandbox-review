import { LightningElement, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDashboard from '@salesforce/apex/WelcomeDashboardController.getDashboard';
import getTodayAttendanceStatus from '@salesforce/apex/WelcomeDashboardController.getTodayAttendanceStatus';

export default class WelcomeDashboard extends NavigationMixin(LightningElement) {
    @track d;                 // DashboardDTO
    @track attnMarked = false;
    @track markedLabel = '';
    @track eodMarked = false;
    @track eodLabel = '';
    showAttnActions = false;
    error;

    // circumference of an r=15.9 ring in a 42x42 viewBox === 100 (percent maths)
    C = 100;

    @wire(getDashboard)
    wiredDashboard({ data, error }) {
        if (data) { this.d = data; this.error = undefined; }
        else if (error) { this.error = error; }
    }

    connectedCallback() {
        this.loadStatus();
        // Re-check when the rep returns to the app/tab (e.g., after submitting EOD),
        // plus a light periodic check as a fallback for in-app tab switches.
        this._onReturn = () => { if (!document.hidden) this.loadStatus(); };
        document.addEventListener('visibilitychange', this._onReturn);
        window.addEventListener('focus', this._onReturn);
        this._poll = setInterval(() => this.loadStatus(), 15000);
    }

    disconnectedCallback() {
        document.removeEventListener('visibilitychange', this._onReturn);
        window.removeEventListener('focus', this._onReturn);
        if (this._poll) { clearInterval(this._poll); this._poll = null; }
    }

    loadStatus() {
        getTodayAttendanceStatus()
            .then((data) => {
                if (!data) return;
                if (data.marked) {
                    this.attnMarked = true;
                    this.markedLabel = `Attendance marked: ${data.status} at ${this.fmtTime(data.markedTime)}`;
                }
                if (data.eodMarked) {
                    this.eodMarked = true;
                    this.eodLabel = `EOD has been Submitted for Today at ${this.fmtTime(data.eodTime)}`;
                    // nothing more to watch once EOD is in — stop polling
                    if (this._poll) { clearInterval(this._poll); this._poll = null; }
                }
            })
            .catch(() => {});
    }

    get showEodBar() { return !this.eodMarked; }

    // ---- Mark Attendance bar -------------------------------------------------
    get showAttnBar() { return !this.attnMarked; }

    toggleAttnActions() { this.showAttnActions = !this.showAttnActions; }

    get todayLabel() {
        const dt = new Date();
        return dt.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
    }

    // Spec: clicking Present/Leave redirects to the EXISTING Attendance page with
    // today's date pre-selected. That page is the current `attendance` component —
    // it already renders Present Type (RoleWorkTypeController.getAllowedWorkTypesForCurrentUser)
    // and selfie capture (AttendanceMgtController.uploadSelfie) and performs the save.
    // Nothing about that flow changes; we only route into it and pass the chosen
    // status. This dashboard reflects the result on return via getTodayAttendanceStatus.
    goToAttendance() {
        // Opens the existing "Apply Attendance" tab (Attendance_Master) — the
        // rep attendance-marking screen with Present Type + selfie, unchanged.
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: { apiName: 'Attendance_Master' }
        });
    }

    // ---- Formatting ----------------------------------------------------------
    inr(v) {
        if (v === undefined || v === null) return '₹0';
        return new Intl.NumberFormat('en-IN', {
            style: 'currency', currency: 'INR', maximumFractionDigits: 0
        }).format(v);
    }
    fmtTime(dtStr) {
        return new Date(dtStr).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' });
    }
    // rounded whole number with Indian grouping, no currency symbol
    num(v) {
        if (v === undefined || v === null) return '0';
        return new Intl.NumberFormat('en-IN', { maximumFractionDigits: 0 }).format(v);
    }
    isoToday() {
        return new Date().toISOString().slice(0, 10);
    }

    // ---- Derived display values ---------------------------------------------
    get attendance() { return this.d ? this.d.attendance : {}; }
    get outlets()    { return this.d ? this.d.outlets : {}; }
    get beat()       { return this.d ? this.d.beat : {}; }
    get rings()      { return this.d ? this.d.rings : {}; }

    get throughPutInr() { return this.inr(this.outlets.throughPut); }
    get throughPutRounded() { return this.num(this.outlets.throughPut); }
    get orderThroughPutR()  { return this.d ? this.num(this.d.order.throughPut) : '0'; }
    get orderValueR()       { return this.num(this.rings.orderValue); }
    get saleValueR()        { return this.num(this.rings.saleValue); }
    get targetPct()  { return this.d ? this.d.target.percent : 0; }
    get targetAmt()  { return this.d ? this.inr(this.d.target.achievement) : '₹0'; }
    get targetOf()   { return this.d ? `of ${this.inr(this.d.target.monthlyTarget)}` : ''; }
    get daysLeft()   { return this.d ? `${this.d.target.daysLeft} days left` : ''; }
    get barStyle()   { return `width:${this.targetPct}%`; }

    get beatTitle() {
        if (!this.d) return '';
        return `${this.beat.beatName || '—'} (${this.beat.beatOutletCount || 0})`;
    }

    get orderTotalInr() { return this.d ? this.inr(this.d.order.totalOrderValue) : '₹0'; }
    get lpc()           { return this.d ? this.d.order.lpc : 0; }
    get orderThroughPut(){ return this.d ? this.d.order.throughPut : 0; }

    // Attendance ring dash arrays (Present, Half Day, Leave, Absent share workingDays base)
    get presentDash() { return this.dash(this.attendance.present, this.attendance.workingDays); }
    get halfDayDash() { return this.dash(this.attendance.halfDay, this.attendance.workingDays); }
    get leaveDash()   { return this.dash(this.attendance.leaveCount, this.attendance.workingDays); }
    get absentDash()  { return this.dash(this.attendance.absent, this.attendance.workingDays); }
    // offset = 25 - (sum of prior segment percents), matching the SVG start-at-top convention
    get halfDayOffset() { return 25 - this._p('present'); }
    get leaveOffset()   { return 25 - this._p('present') - this._p('halfDay'); }
    get absentOffset()  { return 25 - this._p('present') - this._p('halfDay') - this._p('leaveCount'); }
    _p(field) { return this.pct(this.attendance[field], this.attendance.workingDays); }

    // Ring helpers: dash = "filled gap", offset rotates so first segment starts at top (25)
    pct(part, whole) { return (!whole) ? 0 : (part / whole) * 100; }
    dash(part, whole) { const p = this.pct(part, whole); return `${p} ${100 - p}`; }

    get tcPcDash()  { const p = this.beat.tcPcPercent || 0; return `${p} ${100 - p}`; }
    get dfPcDash()  { const p = this.beat.dfPcPercent || 0; return `${p} ${100 - p}`; }
    get fillDash()  { const p = this.d ? this.d.rings.fillRatePercent : 0; return `${p} ${100 - p}`; }
    get deliveryDash(){ const p = this.d ? this.d.rings.deliveryPercent : 0; return `${p} ${100 - p}`; }
}