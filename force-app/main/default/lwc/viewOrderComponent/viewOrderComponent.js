import { LightningElement, api, track, wire } from 'lwc';
import getOrdersByAccountForVisitTask from '@salesforce/apex/VisitController.getOrdersByAccountForVisitTask';
import {  NavigationMixin } from 'lightning/navigation';

export default class ViewOrderComponent  extends NavigationMixin(LightningElement){
    @track showViewOrderComponent;
    @track latestOrders = [];
    @track visitTaskId ;
    @api recordId;
@track visitTaskIdTest;
@track showVisitAccDetailComponent=false;
        //This method will be called when component loaded which will show view order component

    connectedCallback() {
        this.showViewOrderComponent = true;  // Show the child component
        this.visitTaskId = this.recordId;
        localStorage.setItem('visitedViewOrder', true);
        this.loadLatestOrders();
    }
 //This method will be called to load all orders related to visit task which has been passed
     loadLatestOrders() {
         
            if (this.visitTaskId) {
                getOrdersByAccountForVisitTask({ visitTaskId: this.visitTaskId })
                    .then(result => {
    
                        // Validate result and process orders
                        if (result && result.length > 0) {
                            this.latestOrders = result.map(order => ({
                                ...order,
                                formattedDate: this.formatDate(order.CreatedDate),
                                formattedOrderValue: `₹${(order.Total_Order_Value__c || 0).toFixed(2)}`
                            }));
                          
                         
                        } else {
                            this.latestOrders = [];
           
                        }
                    })
                    .catch(error => {
                        console.error('Error fetching orders from Apex:', error);
                        this.latestOrders = [];
                    
                    });
            } else {
                console.error('visitTaskId ID is missing or invalid');
            }
        }
//This method will be called to  format the order date
        formatDate(dateString) {
            if (!dateString) return '';
            const date = new Date(dateString);
            const day = String(date.getDate()).padStart(2, '0');
            const month = String(date.getMonth() + 1).padStart(2, '0');
            const year = date.getFullYear();
            return `${day}/${month}/${year}`;
        }
        //This method will be called to  show Order Detail Page and Order line items
        handleOrderLinkClick(event) {
            const orderId = event.currentTarget.getAttribute('data-orderlink-id'); // Access the custom attribute
            if (orderId) {
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: orderId,
                        objectApiName: 'Order__c',
                        actionName: 'view'
                    }
                });
            }
        }
     //This method will be called to  show the parent component which is Visit Task
        backViewOrderAction(){
            this.showViewOrderComponent = false;

            localStorage.removeItem(`visitedViewOrder`);
          //  window.location.reload();
   this.showVisitAccDetailComponent=true;
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
}