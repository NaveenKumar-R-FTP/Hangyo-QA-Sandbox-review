import { LightningElement, api, track, wire } from 'lwc';
import getRetailerTargets from '@salesforce/apex/RetailerTargetController.getRetailerTargets';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveFile from '@salesforce/apex/RetailerTargetController.saveFile';
import { NavigationMixin } from 'lightning/navigation';
const columns = [
    { label: 'Account Id', fieldName: 'Id' },
    { label: 'Retailer Name', fieldName: 'Name' },                
    { label: 'Retailer Address', fieldName: 'Shipping_Address_text__c' },
    { label: 'Retailer Location', fieldName: 'Location_Text__c' },
    { label: 'Target Amount', fieldName: 'Target_Amount__c' }
    ];

export default class uploadRetailerTargetCSV extends NavigationMixin(LightningElement){
    @track retailerTarget = [];
    @track wiredDataResult;

    columnHeader = [
        'Account Id',
        'Retailer Name', 
        'Retailer Address', 
        'Retailer Location',
        'Target Amount'
    ];

    @api recordid;
    @track columns = columns;
    @track data;
    @track fileName = '';
    @track UploadFile = 'Upload CSV File';
    @track showLoadingSpinner = false;
    @track isTrue = false;
    selectedRecords;
    filesUploaded = [];
    file;
    fileContents;
    fileReader;
    content;
    MAX_FILE_SIZE = 1500000;

    //Get Retailer target data          
    @wire(getRetailerTargets)
    wiredData({ error, data }) {
        if (data) { 
            this.retailerTarget = data;
        } else if (error) {
            this.showToast('Error', 'Error fetching retailer targets.', 'error');
        }
    }                     

    // Export the CSV data 
    exportRetailerTargetData() {
        if (!this.retailerTarget || this.retailerTarget.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'No Retailer are assigned to you.',
                    variant: 'error'
                })
            );
          throw this.showToast('Warning', 'No data available to export.', 'warning') || new Error('No data to export');
          return;
        }

        // Prepare the HTML table
        let doc = '<table>';
        doc += '<style>';
        doc += 'table, th, td { border: 1px solid black; border-collapse: collapse; }';
        doc += '</style>';
        
        // Add table headers
        doc += '<tr>';
        this.columnHeader.forEach(header => {
            doc += `<th>${header}</th>`;
        });
        doc += '</tr>';
        
        // Add data rows
        this.retailerTarget.forEach(account => {
            const { 
                Id, 
                Name, 
                Shipping_Address_text__c = '', 
                Location_Text__c = '', 
                Retailer_Targets__r 
            } = account;

            if (Retailer_Targets__r && Retailer_Targets__r.length > 0) {
                Retailer_Targets__r.forEach(target => {
                    doc += '<tr>';
                    doc += `<td>${Id}</td>`;
                    doc += `<td>${Name}</td>`;
                    doc += `<td>${Shipping_Address_text__c}</td>`;
                    doc += `<td>${Location_Text__c}</td>`;
                    //doc += `<td>${target.Target_Amount__c || ''}</td>`;
                    doc += `<td>${target.Amount__c || '00'}</td>`;
                    doc += '</tr>';
                });
            } else {
                doc += '<tr>';
                doc += `<td>${Id}</td>`;
                doc += `<td>${Name}</td>`;
                doc += `<td>${Shipping_Address_text__c}</td>`;                            
                doc += `<td>${Location_Text__c}</td>`;
                doc += '<td></td>';
                doc += '</tr>';
            }
        });

        doc += '</table>';

        // Create a Blob and trigger download
        const element = 'data:application/vnd.ms-excel,' + encodeURIComponent(doc);
        const downloadElement = document.createElement('a');
        downloadElement.href = element;
        downloadElement.target = '_self';
        downloadElement.download = 'Retailer Data.xls';
        document.body.appendChild(downloadElement);
        downloadElement.click();
        document.body.removeChild(downloadElement);
    }

    // Handle file upload input event
    handleFilesChange(event) {
        if (event.target.files.length > 0) {                    
            this.filesUploaded = event.target.files;                    
            this.fileName = this.filesUploaded[0].name;                    
        }                    
    }
    //Handle Save to Usert the Retailer target
    handleSave() {                    
        if (this.filesUploaded.length > 0) {                    
            this.uploadFile();                    
        } else {
            //this.fileName = 'Please select a CSV file to upload!!';       
            this.dispatchEvent(                    
                new ShowToastEvent({                    
                    title: 'Error!!',                    
                    message: 'Please upload a CSV file!',                    
                    variant: 'error',                    
                    }),                    
            );               
        }                    
    }
    
    // Validation before insertion of records
    validateAmount(amountValue) {
        const regex = /^-?\d+(\.\d+)?$/; // Matches numbers or decimals
        return regex.test(amountValue);
    }


    // File upload 
    uploadFile() {                    
        if (this.filesUploaded[0].size > this.MAX_FILE_SIZE) {
            this.showToast('Error', 'File size is too large.', 'error');
        return;
        }
       
        this.showLoadingSpinner = true;                    
        this.fileReader = new FileReader();                    
        this.fileReader.onloadend = () => {                    
            this.fileContents = this.fileReader.result;                    
            this.saveFile();                    
        };
            
            this.fileReader.readAsText(this.filesUploaded[0]);                    
    }
    
    // Save file with validation check
    saveFile() {                    
        try {    
            
            // Check if the file is a CSV before proceeding
        const fileExtension = this.filesUploaded[0].name.split('.').pop().toLowerCase();
        if (fileExtension !== 'csv') {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Please upload a CSV file. Other file formats are not supported.',
                    variant: 'error',
                })
            );
            return;
        }           
            saveFile({ base64Data: JSON.stringify(this.fileContents), cdbId: this.recordid })                    
                .then(result => {  
                                      
                    if (result === null || result.length === 0) {                    
                        this.dispatchEvent(                    
                            new ShowToastEvent({                    
                                title: 'Warning',                    
                                message: 'The CSV file does not contain any data',                    
                                variant: 'warning',                    
                                }),                    
                        );                    
                    }
                    
                    else {                    
                        this.data = result;                    
                        this.fileName = this.fileName + ' – Uploaded Successfully';                    
                        this.isTrue = false;                    
                        this.showLoadingSpinner = false;                    
                        this.dispatchEvent(                    
                            new ShowToastEvent({                    
                                title: 'Success!!',                    
                                message: this.filesUploaded[0].name + ' – Uploaded Successfully!!!',                    
                                variant: 'success',                    
                                }),                    
                        );   
                        this.navigateToRetailerTargetListView();         
                        setTimeout(() => {
                            window.location.reload();
                        }, 100);
                        return;         
                    }                    
                })                    
                .catch(error => {                                      
                    this.showLoadingSpinner = false;                    
                    this.dispatchEvent(                    
                        new ShowToastEvent({                    
                            title: 'Error while uploading File, Please check the following...',                    
                            message: `1. Only Amount should be Changed.\n2. Amount should be correct Decimal\n\nDetails.`,                  
                            variant: 'error',                                                    
                            }),
                        
                    );
                    
                });
            
        } catch (error) {                                       
            this.showLoadingSpinner = false;                    
            this.dispatchEvent(                    
                new ShowToastEvent({                    
                    title: 'Error',                    
                    message: 'An unexpected error occurred.',                    
                    variant: 'error',                    
                    }),                    
            );                    
        }  
    }

    // Navigation after Save
    navigateToRetailerTargetListView() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Retailer_Target__c',
                actionName: 'list'
            },
            state: {
                filterName: 'My_Retailer_Target'
            }
        });
    }
}