import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class DailySummaryParent extends NavigationMixin(LightningElement) {

    @api parentUserId; // will be passed from parent component

    connectedCallback() {
        console.log('parentUserId received in DailySummaryParent: ', this.parentUserId);
    }

    navigateToDetails() {
        console.log('Navigating to DailySummary tab with parentId:', this.parentUserId);
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Daily_Summary_Child' // Salesforce tab name
            },
            state: {
                //c__parentId: this.parentUserId // Pass dynamically to tab
               //c__parentId: '005GB00000bS6QrYAK'
            }
        });
    }
  /* navigateToDetails() {
    const url = `/lightning/n/Daily_Summary_Child?c__parentId=${this.parentUserId}`;
    this[NavigationMixin.Navigate]({
        type: 'standard__webPage',
        attributes: {
            url
        }
    });
}*/

}