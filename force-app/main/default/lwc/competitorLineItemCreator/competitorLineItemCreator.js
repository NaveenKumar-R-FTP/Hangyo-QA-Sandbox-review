import { LightningElement, api, wire, track } from 'lwc';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import ICE_CREAM_BRAND_FIELD from '@salesforce/schema/Competitor__c.Ice_Cream_Brand__c';
import COMPETITOR_OBJECT from '@salesforce/schema/Competitor__c';
import createLineItems from '@salesforce/apex/CompetitorLineItemController.createCompetitorWithLineItems';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Local storage keys
const STORAGE_KEY = 'competitorFormState';
const INFO_KEY = 'competitorinfo';

export default class CompetitorLineItemCreator extends LightningElement {
    @api recordId;
        @track visitTaskId ;
    @track brandOptions = [];
    @track selectedBrands = [];
    @track lineItems = [];
    @track showcompetitorinfo = true;
@track visitTaskIdTest;
@track showVisitAccDetailComponentInComp=false;
    @wire(getObjectInfo, { objectApiName: COMPETITOR_OBJECT })
    competitorInfo;

    connectedCallback() {
                this.visitTaskId = this.recordId;

        // Load persisted state when component initializes
        const savedState = localStorage.getItem(STORAGE_KEY);
        if (savedState) {
            try {
                const state = JSON.parse(savedState);
                this.selectedBrands = state.selectedBrands || [];
                this.lineItems = state.lineItems || [];
            } catch(error) {
     
                this.showToast('Error', error.body?.message || error.message, 'error');

            }
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$competitorInfo.data.defaultRecordTypeId',
        fieldApiName: ICE_CREAM_BRAND_FIELD
    })
    wiredPicklistValues({ error, data }) {
        if (data) {
            this.brandOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
            localStorage.setItem(INFO_KEY, 'true');
        } else if (error) {
            this.showToast('Error', error.body?.message || 'Error fetching picklist values', 'error');
            this.brandOptions = [];
        }
    }

    handleBrandChange(event) {
        const selectedValues = event.detail.value;
        const previousLineItems = this.lineItems;
        
        const existingItemsMap = new Map();
        previousLineItems.forEach(item => existingItemsMap.set(item.value, item));
    
        this.lineItems = selectedValues.map(brandValue => {
            const existingItem = existingItemsMap.get(brandValue);
            if (existingItem) return existingItem;
            
            const brandOption = this.brandOptions.find(opt => opt.value === brandValue);
            return {
                value: brandValue,
                label: brandOption?.label || brandValue,
                labelWithQuantity: brandOption ? `${brandOption.label} Quantity` : 'Quantity',
                quantity: null,
                description: null
            };
        });
    
        this.selectedBrands = selectedValues;
        this.saveState();
    }

    handleQuantityChange(event) {
        const value = event.target.dataset.value;
        this.lineItems = this.lineItems.map(item =>
            item.value === value ? { ...item, quantity: event.target.value } : item
        );
        this.saveState();
    }

    handleDescriptionChange(event) {
        const value = event.target.dataset.value;
        this.lineItems = this.lineItems.map(item =>
            item.value === value ? { ...item, description: event.target.value } : item
        );
        this.saveState();
    }

    saveState() {
        // Save current state to localStorage
        const state = {
            selectedBrands: this.selectedBrands,
            lineItems: this.lineItems
        };
        localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    }

    clearStorage() {
        // Remove all related storage items
        localStorage.removeItem(STORAGE_KEY);
        localStorage.removeItem(INFO_KEY);
    }

    validateInputs() {
        const isValid = this.lineItems.every(item => item.quantity && item.quantity > 0);
        if (!isValid) {
            this.showToast('Error', 'Please enter valid quantities for all selected brands.', 'error');
        }
        return isValid;
    }

    get isSubmitDisabled() {
        return this.selectedBrands.length === 0;
    }

    async handleSubmit() {
        try {
            if (!this.validateInputs()) return;

            const lineItemWrappers = this.lineItems.map(item => ({
                brand: item.value,
                quantity: item.quantity,
                description: item.description
            }));

            await createLineItems({
                visitTaskId: this.recordId,
                lineItems: lineItemWrappers
            });

            this.showToast('Success', 'Competitors created successfully', 'success');
            this.clearStorage();
            this.backToVisitTaskMethod();
        } catch (error) {
            this.showToast('Error', error.body?.message || error.message, 'error');
        }
    }

    backToVisitTaskMethod() {
        this.showcompetitorinfo = false;
        this.resetForm();
         this.showVisitAccDetailComponentInComp=true;
       // window.location.reload();
 this.visitTaskIdTest=this.visitTaskId;
      // Wait for LWC to render the child component before accessing it
    setTimeout(() => {
        const childComponent = this.template.querySelector('c-visit-account-detail-component');
        if (childComponent) {
            childComponent.callMeFromParentTest(this.visitTaskIdTest);
        } else {
            console.error('Child component not found!');
        }
    }, 0); // Delay just enough to let DOM update
    }

    handleBack() {    
        this.clearStorage();
        this.resetForm();
           this.showcompetitorinfo = false;
                  this.showVisitAccDetailComponentInComp=true;

     //   window.location.reload();
         this.visitTaskIdTest=this.visitTaskId;
      // Wait for LWC to render the child component before accessing it
    setTimeout(() => {
        const childComponent = this.template.querySelector('c-visit-account-detail-component');
        if (childComponent) {
            childComponent.callMeFromParentTest(this.visitTaskIdTest);
        } else {
            console.error('Child component not found!');
        }
    }, 0); // Delay just enough to let DOM update
 
    }

    resetForm() {
        this.selectedBrands = [];
        this.lineItems = [];
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}