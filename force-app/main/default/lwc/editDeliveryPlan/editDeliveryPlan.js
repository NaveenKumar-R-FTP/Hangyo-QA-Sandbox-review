import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation'; 
import getDeliveryPlanForEdit from '@salesforce/apex/DeliveryPlanController.getDeliveryPlanForEdit';
import updateDeliveryPlan from '@salesforce/apex/DeliveryPlanController.updateDeliveryPlan';
import getConfirmedInvoices from '@salesforce/apex/DeliveryPlanController.getConfirmedInvoices';
import deleteInvoice from '@salesforce/apex/DeliveryPlanController.deleteInvoice';
import getInvoiceRecordTypeIds from '@salesforce/apex/DeliveryPlanController.getInvoiceRecordTypeIds';

export default class EditDeliveryPlan extends NavigationMixin(LightningElement) {
    @track deliveryPlan = {}; // To hold Delivery Plan data
    
    recordId;  // This will store the recordId retrieved from the URL

    
    @track isLoading = false;
    @track isModalOpen = false;
    @track invoices = [];
    @track filteredInvoices = []; // Filtered invoice list for display
    @track searchTerm = '';
    @track selectedInvoicesWithDetails = []; // Selected invoices with line items
    @track isDriverNumberValid = true;
    @track isDriverNameValid = true;

    invoiceColumns = [
        { label: 'Invoice Number', fieldName: 'Invoice_Number__c', type: 'text' },
        { label: 'Retailer Name', fieldName: 'RetailerName', type: 'text' },
        { label: 'Beat', fieldName: 'Beat__c', type: 'text' },
        { label: 'Quantity', fieldName: 'Total_Quantity__c', type: 'text' },
        { label: 'Grand Total', fieldName: 'Invoice_Amount__c', type: 'text' },
        {
            label: 'Action',
            type: 'button',
            typeAttributes: { label: 'Select', name: 'select_invoice', variant: 'brand' }
        }
    ];

    selectedInvoiceColumns = [
        { label: 'Invoice Number', fieldName: 'Invoice_Number__c', type: 'text' },
        { label: 'Retailer Name', fieldName: 'RetailerName', type: 'text' },
        { label: 'Beat', fieldName: 'Beat__c', type: 'text' },
        { label: 'Quantity', fieldName: 'Total_Quantity__c', type: 'text' },
        { label: 'Grand Total', fieldName: 'Invoice_Amount__c', type: 'text' },
        {
            label: 'Action',
            type: 'button',
            typeAttributes: { label: 'Show', name: 'showLineItems', variant: 'brand' }
        }
    ];

    lineItemColumns = [
        { label: 'Product Name', fieldName: 'ProductName', type: 'text' },
        { label: 'Quantity', fieldName: 'Quantity__c', type: 'number' },
        { label: 'Crate', fieldName: 'Crate', type: 'text' },
        { label: 'Price', fieldName: 'Price__c', type: 'currency' },
        { label: 'UOM', fieldName: 'Uom', type: 'text' },
        { label: 'Total Amount', fieldName: 'totalAmt', type: 'text' }
        
    ];

   

    get aggregatedProducts() {
        const productMap = new Map();

        this.selectedInvoicesWithDetails.forEach((invoice) => {
            invoice.lineItems.forEach((item) => {
                const productName = item.ProductName;
                const crateConversion = item.Product__r?.Crate_Conversion__c || 0;
                console.log('crateConversion :=' , crateConversion);
                if (productMap.has(productName)) {
                    const existingProduct = productMap.get(productName);
                    existingProduct.totalQuantity += item.Quantity;
                    existingProduct.totalPrice += item.totalAmt;
                } else {
                    productMap.set(productName, {
                        productId: item.Product__c,
                        productName: productName,
                        totalQuantity: item.Quantity,
                        unitPrice: item.Price,
                        totalPrice: item.totalAmt,
                        uom: item.Uom,
                        crateConversion: crateConversion // ✅ store it here
                    });
                }
            });
        });

        return Array.from(productMap.values()).map(product => {
            const qty = product.totalQuantity;
            const crateConv = product.crateConversion;
            let crateText = 'N/A';
            console.log('crateConv :=' , crateConv);
            if (crateConv > 0) {
                const crates = Math.floor(qty / crateConv);
                const remaining = qty % crateConv;
                crateText = `${crates} Crate ${remaining} EA`;
            }

            return {
                ...product,
                crateText,
                totalPrice: product.totalPrice.toFixed(2)
            };
        });
    }


    connectedCallback() {

        this.fetchRecordTypeIdsAndLoadData(); // Fetch record type IDs first
    }

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.recordId = currentPageReference.state.recordId;
            console.log('RecordId from URL:', this.recordId);
            if (this.recordId) {
                // Fetch record type IDs first, then load delivery plan
                this.fetchRecordTypeIdsAndLoadData();
            }
        }
    }
    
    fetchRecordTypeIdsAndLoadData() {
        getInvoiceRecordTypeIds()
            .then((data) => {
                this.secondaryInvoiceRecordTypeId = data.SecondaryInvoice;
                this.secondaryUnderSSInvoiceRecordTypeId = data.SecondaryInvoiceUnderSS;
    
                console.log('RecordTypeId (Secondary):', this.secondaryInvoiceRecordTypeId);
                console.log('RecordTypeId (UnderSS):', this.secondaryUnderSSInvoiceRecordTypeId);
    
                // Now safely load delivery plan data
                this.loadDeliveryPlanData();
            })
            .catch((error) => {
                console.error('Error fetching RecordType Ids:', error);
            });
    }
    

    // Fetch Delivery Plan and related records for editing
    loadDeliveryPlanData() {
        getDeliveryPlanForEdit({ deliveryPlanId: this.recordId })
            .then((result) => {
                console.log('Result',result);
                this.deliveryPlan = result.deliveryPlan;
                
                
             // Save all confirmed invoices
            this.invoices = result.confirmedInvoices;

            // Set selected invoices with details
            this.selectedInvoicesWithDetails = result.selectedInvoices.map((deliveryItem) => {
                const invoice = this.invoices.find((inv) => inv.Id === deliveryItem.Invoices__c);
                if (invoice) {
                    console.log('Checking RecordTypeId:', invoice.RecordTypeId);
                    console.log('Expected secondaryInvoiceRecordTypeId:', this.secondaryInvoiceRecordTypeId);
                    console.log('Expected secondaryUnderSSInvoiceRecordTypeId:', this.secondaryUnderSSInvoiceRecordTypeId);
                    return {
                        ...invoice,
                        // RetailerName: invoice.Retailer_Account__r?.Name || 'N/A',              
                        RetailerName:
                        invoice.RecordTypeId === this.secondaryInvoiceRecordTypeId
                            ? invoice.Retailer_Account__r?.Name || 'N/A'
                            : invoice.RecordTypeId === this.secondaryUnderSSInvoiceRecordTypeId
                            ? invoice.Under_SS__r?.Name || 'N/A'
                            : 'N/A',  
                     InvoiceNumber: invoice.Invoice_Number__c || 'N/A',
                        BeatName: invoice.Beat__c || 'N/A',
                        Quantity: invoice.Total_Quantity__c || 'N/A',
                        GrandTotal: invoice.Invoice_Amount__c || 'N/A',
                        showLineItems: false,
                        lineItems: invoice.Invoice_Line_Items__r?.map((item) => ({
                            ...item,
                            ProductName: item.Product__r?.Name || 'N/A',
                            Price: item.Price__c || 0,
                            Quantity: item.Quantity__c || 0,
                            Uom: item.Product__r?.Unit_of_Measure__c || 'N/A',
                            totalAmt: item.Price__c * item.Quantity__c
                        })) || []
                    };
                }
                return null; // Skip if invoice is not found
            }).filter((invoice) => invoice !== null); // Remove any null entries

           // console.log('Selected Invoices:', JSON.stringify(this.selectedInvoicesWithDetails, null, 2));
        })
        .catch((error) => {
            console.error('Error loading delivery plan data:', error);
        });
}

    

   // Fetch confirmed invoices from Apex
    handleOpenModal() {
        this.isLoading = true;

        getConfirmedInvoices()
        .then((result) => {
            this.invoices = result.map((invoice) => ({
                ...invoice,
            RetailerName:
                invoice.RecordTypeId === this.secondaryInvoiceRecordTypeId
                    ? invoice.Retailer_Account__r?.Name || 'N/A'
                    : invoice.RecordTypeId === this.secondaryUnderSSInvoiceRecordTypeId
                    ? invoice.Under_SS__r?.Name || 'N/A'
                    : 'N/A',
                lineItems: invoice.Invoice_Line_Items__r
                    ? invoice.Invoice_Line_Items__r.map((lineItem) => ({
                          ...lineItem,
                          ProductName: lineItem.Product__r?.Name || 'N/A',
                          Uom: lineItem.Product__r?.Unit_of_Measure__c || 'N/A'
                      }))
                    : []
            }));
            this.filteredInvoices = [...this.invoices];
            this.isModalOpen = true;
            this.isLoading = false;
        })
        .catch((error) => {
            this.isLoading = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error fetching invoices',
                    message: error.body.message,
                    variant: 'error'
                })
            );
        });
    }

    // Method to handle search input change
    handleSearchChange(event) {
        this.searchTerm = event.target.value.toLowerCase();

        // Filter invoices based on the search term
        if (this.searchTerm) {
            this.filteredInvoices = this.invoices.filter((invoice) => {
                return (
                    (invoice.Invoice_Number__c && invoice.Invoice_Number__c.toLowerCase().includes(this.searchTerm)) 
                );
            });
        } else {
            // If no search term, display all invoices
            this.filteredInvoices = [...this.invoices];
        }
    }

    // Handle row action in the datatable (select invoice)
    handleRowAction(event) {
        const invoiceId = event.target.dataset.id;
    
        const isAlreadySelected = this.selectedInvoicesWithDetails.some(invoice => invoice.Id === invoiceId);
        
        if (isAlreadySelected) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Warning',
                    message: 'This invoice is already selected!',
                    variant: 'warning'
                })
            );
            return; // Stop execution if invoice is already selected
        }
        
        // Find the invoice in the list
        const index = this.invoices.findIndex(invoice => invoice.Id === invoiceId);
    
        if (index !== -1) {
            const invoice = { ...this.invoices[index] }; // Clone for reactivity
            
            // Prepare invoice with additional details
            const invoiceWithDetails = {
                ...invoice,
                RetailerName:
                invoice.RecordTypeId === this.secondaryInvoiceRecordTypeId
                    ? invoice.Retailer_Account__r?.Name || 'N/A'
                    : invoice.RecordTypeId === this.secondaryUnderSSInvoiceRecordTypeId
                    ? invoice.Under_SS__r?.Name || 'N/A'
                    : 'N/A',    
           InvoiceNumber: invoice.Invoice_Number__c || 'N/A',
                BeatName: invoice.Beat__c || 'N/A',
                Quantity: invoice.Total_Quantity__c || 'N/A',
                GrandTotal: invoice.Invoice_Amount__c || 'N/A',
                showLineItems: false,
                lineItems: invoice.Invoice_Line_Items__r?.map(item => ({
                    ...item,
                    ProductName: item.Product__r?.Name || 'N/A',
                    Price: item.Price__c || 0,
                    Quantity: item.Quantity__c || 0,
                    Uom: item.Product__r?.Unit_of_Measure__c || 'N/A',
                    totalAmt: item.Price__c * item.Quantity__c
                })) || []
            };
    
            console.log(' 1 this.selectedInvoicesWithDetails.length',this.selectedInvoicesWithDetails.length);
            console.log(' 1 this.filteredInvoices.length',this.filteredInvoices.length);
            // Add to selected invoices and remove from table
            this.selectedInvoicesWithDetails = [...this.selectedInvoicesWithDetails, invoiceWithDetails];
            this.filteredInvoices = this.filteredInvoices.filter(inv => inv.Id !== invoiceId);
    
            this.invoices = this.invoices.filter(inv => inv.Id !== invoiceId);
            console.log('till ');
            console.log('this.selectedInvoicesWithDetails.length',this.selectedInvoicesWithDetails.length);
            console.log('this.filteredInvoices.length',this.filteredInvoices.length);
            console.log('this.invoices.length',this.invoices.length);
            if (this.filteredInvoices.length == 0 && this.selectedInvoicesWithDetails.length != 0) {
                this.handleCloseModal();
            }
            // Show toast notification
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: `Invoice added successfully!`,
                    variant: 'success'
                })
            );
            //this.showToast('Success', `Invoice ${invoice.InvoiceNumber} added successfully!`, 'success');
        }
    }

    toggleLineItems(event) {
        const invoiceId = event.target.dataset.id;

        // Find the invoice and toggle its visibility property
        this.selectedInvoicesWithDetails = this.selectedInvoicesWithDetails.map((invoice) => {
            if (invoice.Id === invoiceId) {
                return { ...invoice, showLineItems: !invoice.showLineItems };
            }
            return invoice;
        });
    }


    // Handle closing the modal
    handleCloseModal() {
        this.isModalOpen = false;
    }
    handleDateChange(event) {
        let selectedDate = event.target.value;
        let today = new Date().toISOString().split("T")[0]; // Get today's date in YYYY-MM-DD format
        if (selectedDate < today) {
            console.log("Past dates are not allowed");
            
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Past dates are not allowed.',
                    variant: 'error'
                })
            );
            event.target.value = this.deliveryPlan.Date__c;
            return;
            } else {
            this.deliveryPlan.Date__c = selectedDate;
        }
    }

    handleDriverNameChange(event) {
     //   this.deliveryPlan.Driver_Name__c = event.target.value;
     const inputField = this.template.querySelector('.driver-name-input');
     const value = event.target.value;
 
     // Allow only letters and spaces
     if (/^[a-zA-Z\s]*$/.test(value)) {
         inputField.setCustomValidity('');
         inputField.reportValidity();
         this.isDriverNameValid = true;
         this.deliveryPlan.Driver_Name__c = value;
     } else {
         inputField.setCustomValidity('Driver Name must contain only alphabets.');
         inputField.reportValidity();
         this.isDriverNameValid = false;
     }
    }

    handleDriverNumberChange(event) {
       // this.deliveryPlan.Driver_Number__c = event.target.value;
       const inputField = this.template.querySelector('.driver-number-input');
       const value = event.target.value;
   
       // Check if it matches 0 to 10 digits only
       if (/^\d{0,10}$/.test(value)) {
           inputField.setCustomValidity('');
           inputField.reportValidity();
           this.isDriverNumberValid = true;
           this.deliveryPlan.Driver_Number__c = value;
       } else {
           inputField.setCustomValidity('Driver Number must be a maximum of 10 digits.');
           inputField.reportValidity();
           this.isDriverNumberValid = false;
       }
    }

    handleVehicleNumberChange(event) {
        this.deliveryPlan.Vehicle_Number__c = event.target.value;
    }
    // Handle save action
    handleSave() {
        if (!this.isDriverNumberValid) {
            this.isLoading = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Driver Number must be a maximum of 10 digits.',
                    variant: 'error'
                })
            );
            return;
        }
        if (!this.isDriverNameValid) {
            this.isLoading = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Driver Name must contain only alphabets.',
                    variant: 'error'
                })
            );
            return;
        }
         this.isLoading = true;
            console.log('Before serializing deliveryPlan:', JSON.stringify(this.deliveryPlan));
            // Convert the deliveryPlan object to a JSON string
            const deliveryPlanJson = JSON.stringify(this.deliveryPlan);
             console.log('Serialized deliveryPlanJson:', deliveryPlanJson);
            // Get an array of selected invoice Ids from selectedInvoicesWithDetails
            const selectedInvoiceIds = this.selectedInvoicesWithDetails.map((invoice) => invoice.Id);

            // Convert the selectedInvoiceIds to a JSON string
            const selectedInvoicesJson = JSON.stringify(selectedInvoiceIds);
            const aggregatedProductsJson = JSON.stringify(this.aggregatedProducts);
            
            if(this.deliveryPlan.Date__c == null || this.deliveryPlan.Driver_Name__c == null || this.deliveryPlan.Driver_Number__c == null || this.deliveryPlan.Vehicle_Number__c == null ){
                this.isLoading = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Add Delivery Plan Details',
                        variant: 'error'
                    })
                );
                return;
            }else if(!selectedInvoiceIds || selectedInvoiceIds.length == 0){
                this.isLoading = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error',
                        message: 'Select an invoice before saving.',
                        variant: 'error'
                    })
                );
                return;
            }
            // Call Apex method, passing both JSON strings
            updateDeliveryPlan({
                deliveryPlanJson: deliveryPlanJson,   // Pass the deliveryPlan as a JSON string
                selectedInvoicesJson: selectedInvoicesJson, // Pass the selectedInvoiceIds as a JSON string
                aggregatedProductsJson: aggregatedProductsJson
            })
            .then((result) => {
                console.log('DeliveryPlan Id',result);
                this.isLoading = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Delivery Plan saved successfully!',
                        variant: 'success'
                    })
                );

                
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: result,
                        objectApiName: 'Delivery_Plan__c', // Object API Name
                        actionName: 'view'
                    }
                });
                this.clearForm();
            })
            .catch((error) => {
                this.isLoading = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error saving record',
                        message: error.body.message,
                        variant: 'error'
                    })
                );
            });
    }
    handleDeleteInvoice(event) {
    const invoiceId = event.target.dataset.id;

    // Call Apex method to delete the invoice
    deleteInvoice({ invoiceId })
        .then(() => {
            // Update UI: Remove the deleted invoice from the list
            this.selectedInvoicesWithDetails = this.selectedInvoicesWithDetails.filter(
                invoice => invoice.Id !== invoiceId
            );
            
        })
        .catch(error => {
            this.showToast('Error', 'Failed to delete the invoice: ' + error.body.message, 'error');
        });
   }
    // Clear the form fields
    clearForm() {
        this.deliveryPlan = {
            Date__c: null,
            Driver_Name__c: '',
            Driver_Number__c: '',
            Vehicle_Number__c: ''
        };
        
        this.selectedInvoicesWithDetails = [];
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }
}