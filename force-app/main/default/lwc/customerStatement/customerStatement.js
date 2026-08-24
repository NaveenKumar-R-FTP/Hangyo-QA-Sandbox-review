// v3.1 - closes dropdown on outside click / focus-away
import { LightningElement, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import getContextAndCustomers from '@salesforce/apex/CustomerStatementController.getContextAndCustomers';
import getStatement from '@salesforce/apex/CustomerStatementController.getStatement';
import JSPDF from '@salesforce/resourceUrl/jspdf';

export default class CustomerStatement extends LightningElement {

    @track customers        = [];
    @track selectedCustomer = '';
    @track customerLabel    = 'Customer';
    @track accountName      = '';
    @track accountType      = '';
    @track searchTerm       = '';
    @track _showList        = false;
    @track fromDate         = this._firstOfMonth();
    @track toDate           = this._today();
    @track result           = null;
    @track isLoading        = false;
    @track errorMessage     = null;
    @track generatedOn      = '';

    _jsPDFLoaded  = false;
    _currentList  = [];
    _outsideClick = null;   // ← holds the bound listener so we can remove it

    connectedCallback() {
        // ── Outside-click listener ───────────────────────────────────────────
        this._outsideClick = (e) => {
            // If the click target is NOT inside this component's host, close the list
            if (!this.template.host.contains(e.target)) {
                this._closeDropdown();
            }
        };
        document.addEventListener('click', this._outsideClick);

        // ── Load customers ───────────────────────────────────────────────────
        getContextAndCustomers()
            .then(ctx => {
                if (ctx.error) { this.errorMessage = ctx.error; return; }
                this.accountName   = ctx.accountName;
                this.accountType   = ctx.accountType;
                this.customerLabel = ctx.customerLabel;
                this.customers     = (ctx.customers || []).filter(c => c.value && c.label);
            })
            .catch(err => {
                this.errorMessage = 'Could not load data: ' + (err.body ? err.body.message : err);
            });
    }

    disconnectedCallback() {
        // Clean up to avoid memory leaks
        if (this._outsideClick) {
            document.removeEventListener('click', this._outsideClick);
            this._outsideClick = null;
        }
    }

    _firstOfMonth() {
        const d = new Date();
        return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().split('T')[0];
    }
    _today() { return new Date().toISOString().split('T')[0]; }

    // ── Closes the dropdown without clearing the typed text ──────────────────
    _closeDropdown() {
        // Only clear searchTerm if the user never committed to a selection
        if (!this.selectedCustomer) {
            this.searchTerm = '';
        }
        this._showList = false;
    }

    // ── Search dropdown handlers ─────────────────────────────────────────────
    get showList()     { return this._showList && !!this.searchTerm && !this.selectedCustomer && this.filteredList.length > 0; }
    get filteredList() {
        const t = (this.searchTerm || '').toLowerCase().trim();
        if (!t) return [];
        return this.customers
            .filter(c => c.label.toLowerCase().includes(t))
            .map(c => ({
                value: c.value,
                label: c.label,
                cls:   'result-item' + (c.value === this.selectedCustomer ? ' result-selected' : '')
            }));
    }
    get emptyList() { return this.filteredList.length === 0; }

    handleInput(e) {
        this.searchTerm       = e.target.value;
        this.selectedCustomer = '';
        this.result           = null;
        this.errorMessage     = null;
        this._showList        = true;   // open on typing
        this._currentList     = this.filteredList;
    }

    // Called when the search input loses focus
    handleSearchBlur() {
        // Small delay so a mouse-click on a list item fires before the list disappears
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this._closeDropdown();
        }, 200);
    }

    handlePick(e)  {
        e.stopPropagation();
        e.preventDefault();
        const clickedText = e.currentTarget.textContent.trim();
        let opt = this.customers.find(c => c.label === clickedText);
        if (!opt) opt = this.customers.find(c => c.label.includes(clickedText) || clickedText.includes(c.label));
        if (opt) {
            this.selectedCustomer = opt.value;
            this.searchTerm       = opt.label;
            this._showList        = false;
            console.log('Selected ID:', opt.value, 'Label:', opt.label);
        }
    }

    clearSelection() {
        this.selectedCustomer = '';
        this.searchTerm       = '';
        this._showList        = false;
        this.result           = null;
        this.errorMessage     = null;
    }

    // ── Date handlers ────────────────────────────────────────────────────────
    // Both date inputs also close the dropdown (focus-away behaviour)
    handleFromDate(e) {
        this._closeDropdown();
        const val = e.detail ? e.detail.value : e.target.value;
        if (val) {
            this.fromDate     = val;
            this.errorMessage = null;
            console.log('From date set to:', this.fromDate);
        }
    }
    handleToDate(e) {
        this._closeDropdown();
        const val = e.detail ? e.detail.value : e.target.value;
        if (val) {
            this.toDate       = val;
            this.errorMessage = null;
            console.log('To date set to:', this.toDate);
        }
    }

    // ── Generate ─────────────────────────────────────────────────────────────
    handleGenerate(e) {
        if (e) { e.stopPropagation(); e.preventDefault(); }
        this._closeDropdown();   // close if generate is clicked while dropdown is open
        console.log('Generate - sending customerId:', this.selectedCustomer);
        if (!this.selectedCustomer) { this.errorMessage = 'Please select a ' + this.customerLabel + '.'; return; }
        if (!this.fromDate || !this.toDate) { this.errorMessage = 'Please select both dates.'; return; }
        if (this.fromDate > this.toDate) { this.errorMessage = 'From Date cannot be after To Date.'; return; }
        const diffDays = Math.round((new Date(this.toDate) - new Date(this.fromDate)) / (1000*60*60*24));
        console.log('Date range days:', diffDays, 'From:', this.fromDate, 'To:', this.toDate);
        if (diffDays > 90) { this.errorMessage = 'Date range cannot exceed 90 days. Please select a smaller range (max 3 months).'; this.result = null; return; }
        this.errorMessage = null;
        this.result       = null;
        this.isLoading    = true;
        getStatement({ customerId: this.selectedCustomer, fromDate: this.fromDate, toDate: this.toDate })
            .then(data => {
                if (data.errorMessage) { this.errorMessage = data.errorMessage; }
                else {
                    this.result = data;
                    this.generatedOn = new Date().toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric', hour:'2-digit', minute:'2-digit' });
                }
            })
            .catch(err => { this.errorMessage = err.body ? err.body.message : JSON.stringify(err); })
            .finally(() => { this.isLoading = false; });
    }

    // ── Computed ─────────────────────────────────────────────────────────────
    get hasResult()    { return this.result !== null; }
    get headerLabel()  { return this.accountType === 'SuperStockist' ? 'Distributor Account Statement' : 'Retailer Account Statement'; }
    get ownerLabel()   { return this.accountType === 'SuperStockist' ? 'Super Stockist' : 'Distributor'; }
    get customerName() { return this.result ? this.result.customerName  : ''; }

    get enrichedLines() {
        if (!this.result || !this.result.lines) return [];
        return this.result.lines.map((line, idx) => ({
            key:              idx,
            txnDate:          this._fmtDate(line.txnDate),
            txnType:          line.txnType,
            invoiceNumber:    line.invoiceNumber,
            comment:          line.comment,
            formattedDebit:   line.debit  > 0 ? this._fmtCur(line.debit)  : '—',
            formattedCredit:  line.credit > 0 ? this._fmtCur(line.credit) : '—',
            formattedBalance: this._fmtCur(line.balance),
            badgeClass:       this._badgeClass(line.txnType)
        }));
    }

    get formattedOpeningBal()       { return this.result ? this._fmtCur(this.result.openingBalance)   : ''; }
    get formattedClosingBal()       { return this.result ? this._fmtCur(this.result.closingBalance)   : ''; }
    get formattedTotalSales()       { return this.result ? this._fmtCur(this.result.totalSales)       : ''; }
    get formattedTotalReturns()     { return this.result ? this._fmtCur(this.result.totalReturns)     : ''; }
    get formattedTotalCollections() { return this.result ? this._fmtCur(this.result.totalCollections) : ''; }
    get formattedTotalCr()          { return this.result ? this._fmtCur(this.result.totalReturns + this.result.totalCollections) : ''; }

    _fmtCur(val) {
        if (val === null || val === undefined) return '—';
        const n = Math.abs(Number(val));
        const s = n.toLocaleString('en-IN', { minimumFractionDigits:2, maximumFractionDigits:2 });
        return (Number(val) < 0 ? '(' : '') + '₹' + s + (Number(val) < 0 ? ')' : '');
    }
    _fmtPDF(val) {
        if (val === null || val === undefined) return '-';
        const n = Math.abs(Number(val));
        const s = n.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
        return (Number(val) < 0 ? '(' : '') + s + (Number(val) < 0 ? ')' : '');
    }
    _fmtDate(dateStr) {
        if (!dateStr) return '';
        const d = new Date(dateStr + 'T00:00:00');
        return d.toLocaleDateString('en-IN', { day:'2-digit', month:'short', year:'numeric' });
    }
    _badgeClass(type) {
        if (type === 'Sale')        return 'badge badge-sale';
        if (type === 'Sale Cancel') return 'badge badge-cancel';
        if (type === 'Return')      return 'badge badge-cancel';
        if (type === 'Collection')  return 'badge badge-coll';
        return 'badge';
    }

    // ── PDF ───────────────────────────────────────────────────────────────────
    handleDownloadPDF() {
        if (!this._jsPDFLoaded) {
            loadScript(this, JSPDF)
                .then(() => { this._jsPDFLoaded = true; this._generatePDF(); })
                .catch(() => { this.errorMessage = 'PDF library failed to load.'; });
        } else { this._generatePDF(); }
    }

    _generatePDF() {
        try {
            const { jsPDF } = window.jspdf;
            const doc = new jsPDF({ orientation:'landscape', unit:'mm', format:'a4' });
            const r   = this.result;
            const W   = doc.internal.pageSize.getWidth();
            const PINK = [232,0,106], PL = [252,228,240];
            let y = 15;
            doc.setFontSize(16); doc.setFont('helvetica','bold'); doc.setTextColor(...PINK);
            doc.text('Hangyo Ice Creams Pvt. Ltd.', 14, y);
            doc.setFontSize(10); doc.setFont('helvetica','normal'); doc.setTextColor(100,100,100);
            doc.text(this.ownerLabel + ': ' + r.accountName, 14, y+6);
            doc.setFontSize(12); doc.setFont('helvetica','bold'); doc.setTextColor(30,30,30);
            doc.text(this.headerLabel, W-14, y, { align:'right' });
            doc.setFontSize(9); doc.setFont('helvetica','normal'); doc.setTextColor(100,100,100);
            doc.text(this.customerLabel + ': ' + r.customerName, W-14, y+6, { align:'right' });
            doc.text('Period: ' + this.fromDate + '  to  ' + this.toDate, W-14, y+11, { align:'right' });
            doc.text('Generated: ' + this.generatedOn, W-14, y+16, { align:'right' });
            doc.setDrawColor(...PINK); doc.setLineWidth(0.5); doc.line(14, y+19, W-14, y+19);
            y += 25;
            doc.setFillColor(...PL); doc.rect(14, y, W-28, 14, 'F');
            const si = [['Opening Bal',this._fmtPDF(r.openingBalance)],['Total Sales',this._fmtPDF(r.totalSales)],['Returns',this._fmtPDF(r.totalReturns)],['Collections',this._fmtPDF(r.totalCollections)],['Closing Bal',this._fmtPDF(r.closingBalance)]];
            const cw = (W-28)/5;
            si.forEach((item,i) => {
                const x = 14+i*cw+cw/2;
                doc.setFontSize(8); doc.setFont('helvetica','normal'); doc.setTextColor(176,0,79);
                doc.text(item[0], x, y+5, { align:'center' });
                doc.setFontSize(10); doc.setFont('helvetica','bold'); doc.setTextColor(30,30,30);
                doc.text(item[1], x, y+11, { align:'center' });
            });
            y += 19;
            const cols = [
                { header:'Date',        key:'txnDate',      w:28, align:'left'  },
                { header:'Type',        key:'txnType',      w:28, align:'left'  },
                { header:'Invoice No.', key:'invoiceNumber',w:38, align:'left'  },
                { header:'Debit (Dr)',  key:'debit',        w:35, align:'right' },
                { header:'Credit (Cr)',key:'credit',        w:35, align:'right' },
                { header:'Balance',    key:'balance',       w:35, align:'right' },
                { header:'Remark',     key:'comment',       w:0,  align:'left'  }
            ];
            cols[6].w = W-28-cols.slice(0,6).reduce((a,c)=>a+c.w,0);
            doc.setFillColor(...PINK); doc.rect(14, y, W-28, 7, 'F');
            doc.setFontSize(8); doc.setFont('helvetica','bold'); doc.setTextColor(255,255,255);
            let x = 14;
            cols.forEach(col => { const tx = col.align==='right'?x+col.w-2:x+2; doc.text(col.header, tx, y+5, { align:col.align }); x+=col.w; });
            y += 7;
            doc.setFillColor(253,240,247); doc.rect(14, y, W-28, 6, 'F');
            doc.setFont('helvetica','italic'); doc.setFontSize(8); doc.setTextColor(100,100,100);
            const bx = 14+cols.slice(0,6).reduce((a,c)=>a+c.w,0)-2;
            doc.text('Opening Balance', bx-cols[5].w-2, y+4, { align:'right' });
            doc.text(this._fmtPDF(r.openingBalance), bx, y+4, { align:'right' });
            y += 6;
            doc.setFont('helvetica','normal');
            r.lines.forEach((line,i) => {
                if (y>185) { doc.addPage(); y=15; }
                doc.setFillColor(...(i%2===0?[255,255,255]:[252,228,240]));
                doc.rect(14, y, W-28, 6, 'F');
                doc.setTextColor(30,30,30); doc.setFontSize(8);
                const row = { txnDate:this._fmtDate(line.txnDate), txnType:line.txnType, invoiceNumber:line.invoiceNumber||'', debit:line.debit>0?this._fmtPDF(line.debit):'', credit:line.credit>0?this._fmtPDF(line.credit):'', balance:this._fmtPDF(line.balance), comment:(line.comment||'').substring(0,25) };
                let rx=14; cols.forEach(col => { const val=row[col.key]||''; const tx=col.align==='right'?rx+col.w-2:rx+2; doc.text(val, tx, y+4, { align:col.align }); rx+=col.w; });
                y += 6;
            });
            doc.setFillColor(...PL); doc.rect(14, y, W-28, 7, 'F');
            doc.setFont('helvetica','bold'); doc.setFontSize(8); doc.setTextColor(30,30,30);
            doc.text('TOTAL', 16, y+5);
            let tx2 = 14+cols[0].w+cols[1].w+cols[2].w+cols[3].w-2;
            doc.text(this._fmtPDF(r.totalSales), tx2, y+5, { align:'right' });
            tx2+=cols[3].w; doc.text(this._fmtPDF(r.totalReturns+r.totalCollections), tx2, y+5, { align:'right' });
            tx2+=cols[4].w; doc.text(this._fmtPDF(r.closingBalance), tx2, y+5, { align:'right' });
            y += 12;
            doc.setDrawColor(...PINK); doc.line(14, y, W-14, y); y+=4;
            doc.setFont('helvetica','italic'); doc.setFontSize(8); doc.setTextColor(150,150,150);
            doc.text('System-generated statement. No signature required. | Hangyo Ice Creams Pvt. Ltd.', 14, y);
            doc.setFont('helvetica','bold'); doc.setTextColor(...PINK);
            doc.text('Net Outstanding: ' + this._fmtPDF(r.closingBalance), W-14, y, { align:'right' });
            const fn = `Statement_${r.customerName.replace(/\s+/g,'_')}_${this.fromDate}_to_${this.toDate}.pdf`;
            doc.save(fn);
        } catch(err) { this.errorMessage = 'PDF generation failed: ' + err.message; }
    }
}