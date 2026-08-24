import { LightningElement, api, track } from 'lwc';
import getPdfUrl from '@salesforce/apex/ClaimHeaderPDFController.getInvoicePdfUrl';
import { CloseActionScreenEvent } from 'lightning/actions';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class Generatetopsheet extends LightningElement {

    @api recordId;

    connectedCallback() {
        getPdfUrl().then((result) => {
            setTimeout(() => {
                console.log('OUTPUT : ', this.recordId);
                console.log('OUTPUT : ', JSON.stringify(result));
                window.open(result + this.recordId, '_blank');
                this.dispatchEvent(new CloseActionScreenEvent());
            }, 300);
        }).catch((err) => {
            this.showtost('Error', err.body.message, 'error');
        });
    }

    showtost(title, msg, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: msg,
                variant: variant,
            }),
        );
    }

}