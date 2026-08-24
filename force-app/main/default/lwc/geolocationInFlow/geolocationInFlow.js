//This Js is created by Ajay and is used to fetch location in Salesforce flows

import { LightningElement, api} from 'lwc';

export default class GeolocationInFlow extends LightningElement {
    @api latitude;
    @api longitude;

//fetches the location soon this component is called from flow

    connectedCallback() {
        if (navigator.geolocation) {
            navigator.geolocation.getCurrentPosition(position => {
                this.latitude = Number(position.coords.latitude);
                this.longitude = Number(position.coords.longitude);
                this.dispatchFlowValues();
            }, error => {
                console.error('Error fetching location', error);
            });
        } else {
            console.error('Geolocation is not supported by this browser.');
        }
    }

    dispatchFlowValues() {
        const locationEvent = new CustomEvent('locationupdate', {
            detail: { 
            latitude: Number(this.latitude),  // Ensure it's a number
            longitude: Number(this.longitude) // Ensure it's a number
        }
        });
        this.dispatchEvent(locationEvent);
    }
}