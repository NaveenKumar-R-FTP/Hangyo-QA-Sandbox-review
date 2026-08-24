import { LightningElement, track } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import { NavigationMixin } from 'lightning/navigation';
import getKpiCounts from '@salesforce/apex/AdditionalScreenMockupController.getKpiCounts';

export default class AdditionalScreenMockup extends NavigationMixin(LightningElement) {

    //distributorCount = 0;
    //beatsCount = 0;
    //outletsCount = 0;
    plannedCount = 0;
    //upcCount = 0;
    //utcCount = 0;
    lpcCount = 0;
    tlcCount = 0;
    qtyCount = 0;
    netPayCount = 0;
    lpcCountRounded = 0;

    @track userId = USER_ID;

    connectedCallback() {
        this.loadMetrics();
    }

    loadMetrics() {
        getKpiCounts({ userId: USER_ID })
            .then(data => {
                //this.distributorCount = data.Distributor;
                //this.beatsCount = data.Beats;
                //this.outletsCount = data.Outlets;
                this.plannedCount = data.Planned;
                //this.upcCount = data.UPC;
                //this.utcCount = data.UTC;
                //this.lpcCount = data.LPC;
                //this.lpcCountRounded = Number(data.LPC).toFixed(1);
                this.tlcCount = data.TLC;
                this.qtyCount = data.QTY;
                this.netPayCount = data.NetPay;

                if (this.plannedCount > 0) {
                    this.lpcCount = this.tlcCount / this.plannedCount;
                } else {
                    this.lpcCount = 0;
                }
                this.lpcCountRounded = Number(this.lpcCount).toFixed(2);

            })
            .catch(error => {
                console.error('Error fetching dashboard metrics', error);
            });
    }

    handleSeeDetails() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Additional_Screen_Child'
            }
        });
    }
}