import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class RedirectToRecord extends NavigationMixin(LightningElement) {
    // API property to accept the record ID from the flow
    @api recordId;

    connectedCallback() {
    if (this.recordId) {
        this.redirectToRecordPage();
    } else {
        console.log('No record ID provided.');
        // Optionally show a message to the user or stop the navigation.
    }
}

    // Redirect the user to the record detail page
    redirectToRecordPage() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                actionName: 'view',
            },
        });
    }
}