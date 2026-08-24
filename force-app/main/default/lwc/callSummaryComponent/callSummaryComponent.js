import { LightningElement, track } from 'lwc';
import getCallSummary from '@salesforce/apex/CallSummaryController.getCallSummary';

export default class CallSummaryComponent extends LightningElement {

    @track summary = {
        tc: 0,
        pc: 0,
        sc: 0,
        netValue: 0
    };

    filterType = 'FTD'; // default

    connectedCallback() {
        this.loadData();
    }

    handleFilterChange(event) {
        this.filterType = event.target.value;

        // Always call Apex — ensures FTD gets refreshed too
        this.loadData();
    }

    loadData() {
        getCallSummary({ filterType: this.filterType })
            .then(result => {
                this.summary = {
                    tc: result.tc,
                    pc: result.pc,
                    sc: result.sc,
                    netValue: result.netValue
                };
            })
            .catch(error => {
                console.error('Error while fetching call summary: ', error);
            });
    }

    get formattedNetValue() {
        if (this.summary.netValue == null) return '';
        return new Intl.NumberFormat('en-IN', {
            style: 'currency',
            currency: 'INR',
            maximumFractionDigits: 0
        }).format(this.summary.netValue);
    }
}