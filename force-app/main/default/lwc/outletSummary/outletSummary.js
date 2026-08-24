import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getOutletSummary from '@salesforce/apex/OutletSummaryController.getOutletSummary';

export default class OutletSummary extends NavigationMixin(LightningElement) {
    @api recordId;
    @api parentUserId;

    @track filterType = 'FTD';   // ✅ Default value so page loads immediately
    
    @track data = {
        totalTC: 0,
        productiveCalls: 0,
        upc: 0,
        utcNoOrder: 0,
        zeroOrderCount: 0,
        coveragePct: 0,
        productivity: 0,
        netValue: 0
    };

    // ✅ Always called once when page reference becomes available
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference || !currentPageReference.state) return;

        const state = currentPageReference.state;

        // Read params (whether or not they changed)
        if (state.c__parentUserId) {
            this.parentUserId = state.c__parentUserId;
        }

        if (state.c__periodType) {
            this.filterType = state.c__periodType;
        }

        // Always load data once state arrives
        this.loadData();
    }

    // ❌ No need for data loading here because state is not ready during connectedCallback
    connectedCallback() {}

    handleFilterChange(event) {
        this.filterType = event.target.value;
        this.loadData();
    }

    loadData() {
        const userId = this.recordId || this.parentUserId;

        if (!userId || !this.filterType) return;

        getOutletSummary({ 
            userId: userId, 
            periodType: this.filterType 
        })
        .then(result => {
            if (result) {
                this.data = {
                    totalTC: Number(result.totalTC) || 0,
                    productiveCalls: Number(result.productiveCalls) || 0,
                    upc: Number(result.upc) || 0,
                    utcNoOrder: Number(result.utcNoOrder) || 0,
                    zeroOrderCount: Number(result.zeroOrderCount) || 0,
                    coveragePct: Number(result.coveragePct) || 0,
                    productivity: Number(result.productivity) || 0,
                    netValue: Number(result.netValue) || 0
                };
                console.log('Loaded data:', this.data);
            }
        })
        .catch(error => {
            console.error('Error loading outlet summary:', error);
            this.data = {
                totalTC: 0,
                productiveCalls: 0,
                upc: 0,
                utcNoOrder: 0,
                zeroOrderCount: 0,
                coveragePct: 0,
                productivity: 0,
                netValue: 0
            };
        });
    }

    // LABELS
    get coveragePctLabel() {
        const num = Number(this.data.coveragePct || 0);
        return !isNaN(num) ? num.toFixed(0) + '%' : '0%';
    }

    get productivityLabel() {
        const num = Number(this.data.productivity || 0);
        return !isNaN(num) ? num.toFixed(0) + '%' : '0%';
    }

    get netValueLabel() {
        const num = Number(this.data.netValue || 0);
        return !isNaN(num) ? '$' + num.toFixed(2) : '-';
    }

    // DONUT %
    get productivityPct() {
        const num = Number(this.data.productivity || 0);
        return !isNaN(num) ? num.toFixed(0) : '0';
    }

    get coveragePct() {
        const num = Number(this.data.coveragePct || 0);
        return !isNaN(num) ? num.toFixed(0) : '0';
    }

    get orderedPct() {
        if (this.data.totalTC === 0) return '0';
        return ((Number(this.data.productiveCalls) / Number(this.data.totalTC)) * 100).toFixed(0);
    }

    get productivityDash() {
        return `${Number(this.productivityPct) || 0},100`;
    }

    get coverageDash() {
        return `${Number(this.coveragePct) || 0},100`;
    }

    get orderedDash() {
        return `${Number(this.orderedPct) || 0},100`;
    }

    // SCALING
    get maxKpiValue() {
        return Math.max(
            Number(this.data.totalTC) || 0,
            Number(this.data.upc) || 0,
            Number(this.data.zeroOrderCount) || 0,
            Number(this.data.utcNoOrder) || 0,
            1
        );
    }

    get otcWidth() {
        return `${(Number(this.data.totalTC) / this.maxKpiValue) * 100}%`;
    }

    get upcWidth() {
        return `${(Number(this.data.upc) / this.maxKpiValue) * 100}%`;
    }

    get zeroWidth() {
        return `${(Number(this.data.zeroOrderCount) / this.maxKpiValue) * 100}%`;
    }

    get notVisitedWidth() {
        return `${(Number(this.data.utcNoOrder) / this.maxKpiValue) * 100}%`;
    }

    get totalWidth() {
        return `${(Number(this.data.totalTC) / this.maxKpiValue) * 100}%`;
    }

    get otcStyle() { return `width:${this.otcWidth}`; }
    get upcStyle() { return `width:${this.upcWidth}`; }
    get zeroStyle() { return `width:${this.zeroWidth}`; }
    get notVisitedStyle() { return `width:${this.notVisitedWidth}`; }
    get totalStyle() { return `width:${this.totalWidth}`; }

    handleSeeDetails() {
        const targetUserId = this.recordId || this.parentUserId || '';
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Outlet_Summary_Details_Page'
            },
            state: {
                c__parentUserId: targetUserId,
                c__periodType: this.filterType
            }
        });
    }
}