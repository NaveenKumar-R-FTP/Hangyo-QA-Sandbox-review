import { LightningElement, track, wire } from 'lwc';
import fetchOrderAndLineItems from '@salesforce/apex/SecondaryOrderHandler.ordfetchOrderAndLineItems';
import { showToast } from 'c/dmsUtility';
export default class SecondaryInvoiceFromOrderDetail extends LightningElement {
    @track order = {};
    @track orderLineItems = [];
    @track recordId;
    @track isCounterFlow = false;
    @track priceType = 'MRP';
    orderNumber;
    orderFound = false;
    isLoading = true;

    connectedCallback() {
        const queryParams = new URLSearchParams(window.location.search);
        this.recordId = queryParams.get('recordId');
        console.log('this.recordId',this.recordId);
        // If a recordId is found, fetch its status
        if (this.recordId) {
            this.fetchOrderDetails();
        } else {
            this.showErrorPopup('No record ID provided in the URL.');
        }
    }

    fetchOrderDetails() {
        fetchOrderAndLineItems({ orderNumber: this.recordId })
            .then((result) => {
               if (!result || !result.order || !result.orderItems) {
                    this.dispatchEvent(showToast('Error', 'No Order Found!', [], 'error', ''));
                } else {
                    this.order = result.order;
                    this.orderLineItems = result.orderItems;
                    this.orderFound = true;

                    // Sale_Type__c / Price_Type__c are real fields on Order__c, set for both
                    // Counter Orders and regular DMS Secondary Orders. Trust whatever is
                    // actually stored, regardless of order type — only fall back to 'MRP'
                    // if it's genuinely blank. (Previously this was gated to Counter Orders
                    // only, so every regular Secondary Order silently displayed/priced as
                    // MRP even when Dealer Price was stored.)
                    this.isCounterFlow = this.order.Type__c === 'Counter Order';
                    this.priceType = this.order.Price_Type__c || 'MRP';
                }
            })
            .catch((error) => {
                this.dispatchEvent(showToast('Error', error.body.message, [], 'error', ''));
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleCancelEvent() {
        this.orderFound = false;
    }

    handleSaveEvent() {
        this.orderFound = false;
    }
}