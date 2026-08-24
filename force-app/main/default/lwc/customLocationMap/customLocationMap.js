import { LightningElement, api, wire, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = ['Account.Latitude__c', 'Account.Longitude__c', 'Account.Name'];

export default class AccountLocationMap extends LightningElement {
    @api recordId;

    @track latitude;
    @track longitude;
    @track selectedlocation;
    accountName;

    connectedCallback() {
        console.log('Component initialized with recordId:', this.recordId);
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredAccount({ error, data }) {
        console.log('Wired account result:', { data, error });
        if (data) {
            this.latitude = data.fields.Latitude__c.value;
            this.longitude = data.fields.Longitude__c.value;
            this.accountName = data.fields.Name.value;
        } else if (error) {
            console.error('Error fetching coordinates:', error);
        }
    }

    get hasCoordinates() {
        console.log('Has coordinates:', this.latitude && this.longitude);
        return this.latitude != null && this.longitude != null;
    }

    get mapMarkers() {
        return [
            {
                location: {
                    Latitude: this.latitude,
                    Longitude: this.longitude
                },
                title: this.accountName || 'Retailer Location',
                description: 'Location from Account'
            }
        ];
    }

    get mapCenter() {
        return {
            latitude: this.latitude,
            longitude: this.longitude
        };
    }
 get mapUrl() {
        return `https://www.google.com/maps/search/?api=1&query=${this.latitude},${this.longitude}`;
    }
    openInGoogleMaps() {
        const url = `https://www.google.com/maps/search/?api=1&query=${this.latitude},${this.longitude}`;
        window.open(url, '_blank');
    }
}