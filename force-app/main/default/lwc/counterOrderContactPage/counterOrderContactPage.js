import { LightningElement , track , wire } from 'lwc';
import fetchDistributorData from '@salesforce/apex/CounterOrderProductPageController.fetchDistributorData';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CounterOrderContactPage extends NavigationMixin(LightningElement) {
    // Declare the properties to hold input values
    firstname = '';
    lastname = '';
    email = '';
    phone = '';
    addressline = '';
    State = '';
    country = '';
    postalcode = '';
    City = '';
    company = '';
    gstinNumber = '';
    
    // Declare the showCounterPage flag to control the rendering of the child component
    showCounterPage = false;
    showContactInfoPage = true;

    @wire(fetchDistributorData)
    wiredDistributorData({ error, data }) {
        if (data) {
            console.log('Data :-',data);
            // Parse the first item in the response
            const distributor = JSON.parse(data)[0]; // Assuming only one distributor data is returned
            this.State = distributor.ConBillingState || '';
            this.City = distributor.ConBillingCity || '';
            this.postalcode = distributor.ConBillingPostalCode || '';
            this.country = distributor.ConBillingCountry || '';
            //this.company = distributor.ConName || '';
        } else if (error) {
            this.showToast('Error', 'Failed to fetch distributor data', 'error');
            console.error('Error fetching distributor data:', error);
        }
    }

    // Handle input changes to update the values of the properties
    handleInputChange(event) {
        const field = event.target.name;
        if (field === 'firstname') {
            this.firstname = event.target.value;
        } else if (field === 'lastname') {
            this.lastname = event.target.value;
        } else if (field === 'email') {
            this.email = event.target.value;
        } else if (field === 'phone') {
            this.phone = event.target.value;
        } else if (field === 'addressline') {
            this.addressline = event.target.value;
        }else if (field === 'company') {
            this.company = event.target.value;
        }else if (field === 'gstinNumber') {
            this.gstinNumber = event.target.value;
        }
    }

    handleNext(){
        if(this.firstname == '' || this.phone == ''){
            this.showToast('', 'Kindly fill in both the First Name and Phone fields.', 'error');
        }else{
            this.showContactInfoPage = false;
            this.showCounterPage = true;
            console.log(this.showCounterPage);
        }
    }

    showToast(tilte, message, variant) {
    const event = new ShowToastEvent({
        title: tilte,
        message: message,
        variant: variant
    });
    this.dispatchEvent(event);
    }
}