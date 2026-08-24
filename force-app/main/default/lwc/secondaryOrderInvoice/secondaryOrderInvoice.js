import { LightningElement,track } from 'lwc';
import fetchOrderAndLineItems from '@salesforce/apex/SecondaryOrderHandler.fetchOrderAndLineItems';
import {isNullEmptyUndefined, isNullEmptyUndefinedObject, showToast} from 'c/dmsUtility';


export default class SecondaryOrderInvoice extends LightningElement {

    
    orderNumber;
    searchOrder = true;
    
    @track order = {};
    @track orderLineItems = [];

    handleSearchKeyword(event) {
        const inputBoxName = event.target.name;
        if(inputBoxName == 'orderNumber') {
            this.orderNumber = event.target.value;
        }
    }

    handleSearch() {
        console.log('orderNumber:'+this.orderNumber);
        if(isNullEmptyUndefined(this.orderNumber)) {
            this.dispatchEvent(showToast('Error','Please enter valid Order Name or Order Number to Search!',[],'error',''));
        } else {
            fetchOrderAndLineItems({orderNumber:this.orderNumber}).then(result => {
                console.log('result=' + typeof(result) + ' ' + JSON.stringify(result));
                
                if (isNullEmptyUndefinedObject(result)) {
                    this.dispatchEvent(showToast('Error','No Order Found! Enter correct details and Try Again.',[],'error',''));
                } else if (isNullEmptyUndefinedObject(result.orderItems)) { 
                    this.dispatchEvent(showToast('Error','No products found, Invoice cannot be generated!',[],'error',''));
                } else {
                    this.searchOrder = false;
                    this.order = result.order;
                    this.orderLineItems = result.orderItems;
                    console.log('SecondaryOrderInvoice order *** ' + typeof(this.order) + ' ' + JSON.stringify(this.order));
                    console.log('SecondaryOrderInvoice orderLineItems *** ' + typeof(this.orderLineItems) + ' ' + JSON.stringify(this.orderLineItems));
                }
            }).catch(error => {
                this.dispatchEvent(showToast('Error',error.body.message,[],'error',''));
            });
        }  
    }

    handleCancelEvent(event) {
        console.log('inside parent handleCancelEvent');
        this.orderNumber = '';
        this.searchOrder = true;
    }

    handleSaveEvent(event) {
        console.log('inside parent handleSaveEvent');
        this.orderNumber = '';
        this.searchOrder = true;
    }

}