import { LightningElement, track, wire } from 'lwc';
import fetchDistributorData from '@salesforce/apex/CounterInvoiceController.fetchDistributorData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CounterInvoiceContactPage extends LightningElement {

    firstname   = '';
    lastname    = '';
    email       = '';
    phone       = '';
    addressline = '';
    state       = '';
    country     = 'India';
    postalcode  = '';
    city        = '';
    company     = '';
    gstin       = '';

    @track saleType  = 'Cash Sales';
    @track priceType = 'MRP';
    @track showProductPage     = false;
    @track showContactInfoPage = true;

    get isSaleTypeEvent() { return this.saleType === 'Event'; }
    get isSaleTypeCash()  { return this.saleType === 'Cash Sales'; }
    get isPriceMRP()      { return this.priceType === 'MRP'; }
    get isPriceDealer()   { return this.priceType === 'Dealer Price'; }

    @wire(fetchDistributorData)
    wiredDistributorData({ error, data }) {
        if (data) {
            const parsed = JSON.parse(data);
            if (parsed && parsed.length > 0) {
                const d = parsed[0];
                this.state      = d.ConBillingState || d.PrimaryState || '';
                this.country    = 'India';
                this.postalcode = d.ConBillingPostalCode || '';
                this.city       = d.ConBillingCity || '';
            }
        } else if (error) {
            this.showToast('Error', 'Failed to fetch distributor data', 'error');
        }
    }

    handleSaleTypeChange(event)  { this.saleType  = event.target.value; }
    handlePriceTypeChange(event) { this.priceType = event.target.value; }

    handleInputChange(event) {
        const field = event.target.name;
        this[field] = event.target.value;
    }

    handleGoBack() {
        this.showProductPage     = false;
        this.showContactInfoPage = true;
    }

    handleNext() {
        if (!this.firstname || !this.phone) {
            this.showToast('', 'Please fill in First Name and Phone fields.', 'error');
            return;
        }
        this.showContactInfoPage = false;
        this.showProductPage     = true;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}