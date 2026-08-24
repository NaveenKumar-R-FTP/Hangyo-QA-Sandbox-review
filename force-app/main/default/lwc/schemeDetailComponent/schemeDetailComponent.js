import { LightningElement, api, track, wire } from 'lwc';
import getAllActiveQualityScheme from '@salesforce/apex/OrderProductController.getAllActiveQualityScheme';
import getAllActiveValueScheme from '@salesforce/apex/OrderProductController.getAllActiveValueScheme';
import NO_Quantity_SCHEME_AVAILABLE  from '@salesforce/label/c.No_Quantity_Scheme_Available';
import NO_Value_SCHEME_AVAILABLE  from '@salesforce/label/c.No_Value_Scheme_Available';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class SchemeDetailComponent extends LightningElement {

@track visitTaskIdTest;
@track showVisitAccDetailComponentInSchme=false;
    @track quantitySchemesData = [];
    @track IsAllQuantityScheme = false;
    @track hasQuantitySchemes = false;
    @track noschemeQua='';

    @track valueSchemesData = [];
    @track hasValueSchemes = false;
    @track IsAllValueScheme = false;
    @track noschemeVal='';
    @track showChildComponent;
    @track currentUrl;
    @track visitedQuanitySchemeCheck;
    @track visitedValueSchemeCheck;
    @track isQualityScheme=false;
    @track visitTaskId ;
    @api recordId;
    //This method will be called when component loaded which will show scheme component
    connectedCallback() {
        this.visitTaskId = this.recordId;
    
        localStorage.setItem('visitedScheme', true);
   
        this.showChildComponent = true;  // Show the child component
        this.visitedQuanitySchemeCheck = localStorage.getItem('visitedQuantityScheme');
        if (this.visitedQuanitySchemeCheck) {
            this.showChildComponent = false;

            this.allQuanitySchemeTable();
        }
        this.visitedValueSchemeCheck = localStorage.getItem('visitedValueScheme');
        if (this.visitedValueSchemeCheck) {
            this.showChildComponent = false;
    
            this.allValueSchemeTable();
        }
        

    }

    //This method will be called when back button clicked to show visit task 
    backToVisitAction(){
                  this.showChildComponent=false;
          this.showVisitAccDetailComponentInSchme=true;
                  localStorage.removeItem(`visitedScheme`); 
                //  window.location.reload();
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

    //This method will be called to show All Quantity Scheme
     allQuanitySchemeTable(){
            localStorage.setItem('visitedQuantityScheme', true);

            getAllActiveQualityScheme({})
            .then(result => {
    
                // Validate result and process orders
                if (result && result.length > 0) {
                    this.quantitySchemesData = result;
            this.IsAllQuantityScheme=true;
            this.showChildComponent=false;
            this.hasQuantitySchemes = true;
    
                
                 
                } else {
                   
                    this.quantitySchemesData = [];
                        this.twoButtonClick=false;
                        this.IsAllQuantityScheme=true;
                    this.hasQuantitySchemes = false;
                    this.showChildComponent=false;
                    this.noschemeQua=NO_Quantity_SCHEME_AVAILABLE;
                }
            })
            .catch(error => {
                this.quantitySchemesData = [];
                this.showToast(
                    'Error',
                    error?.body?.message || 'Error fetching quantitySchemesData from Apex',
                    'error'
                );  
            });
           
            
         }
    //This method will be called to show All Value Scheme

           allValueSchemeTable(){
                 localStorage.setItem('visitedValueScheme', true);

                 getAllActiveValueScheme({})
                 .then(result => {
         
                     // Validate result and process orders
                     if (result && result.length > 0) {
                         this.valueSchemesData = result;
                 this.IsAllValueScheme=true;
                 this.showChildComponent=false;
                      this.hasValueSchemes = true;
                       
                      
                     } else {
                         this.valueSchemesData = [];
                         this.hasValueSchemes = false;
                         this.IsAllValueScheme=true;
                         this.twoButtonClick=false;
                         this.showChildComponent=false;
                        this.noschemeVal=NO_Value_SCHEME_AVAILABLE;
                         
                     }
                 })
                 .catch(error => {
                     this.valueSchemesData = [];
                     this.showToast(
                        'Error',
                        error?.body?.message || 'Error fetching valueSchemesData from Apex',
                        'error'
                    );  
               
                 });
                
                 
              }
              //This method will be called to show Quantity Scheme and  Value Scheme buttons

              backQuantitySchemsAction(){
                 this.IsAllQuantityScheme=false;
                 this.showChildComponent=true;
                 localStorage.removeItem(`visitedQuantityScheme`); // Clear the cart from localStorage

             }
              //This method will be called to show Quantity Scheme and  Value Scheme buttons
             backValueSchemsAction(){
                this.IsAllValueScheme=false;
                this.showChildComponent=true;
                localStorage.removeItem(`visitedValueScheme`); 
                
            }
               

        
 //This method is used to show toast message
 showToast(title, message, variant) {
    const evt = new ShowToastEvent({
        title: title,
        message: message,
        variant: variant,
    });
    this.dispatchEvent(evt);
}

   
}