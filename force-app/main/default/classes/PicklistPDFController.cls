public with sharing class PicklistPDFController {
    public Id deliveryPlanId { get; set; } 
    public List<Picklist__c> picklistRecords { get; private set; }
    public Contact loggedInContact { get; set; } // Renamed to loggedInContact for clarity
    public List<Delivery_Plan__c> deliveryPlans { get; set; }
    public String formattedDate { get; set; } 

    
    // Constructor
    public PicklistPDFController() {
        // Capture the Delivery Plan ID from the page URL
        deliveryPlanId = ApexPages.currentPage().getParameters().get('id');

        // Query the Picklist records only if a valid ID is provided
        if (deliveryPlanId != null) {
            picklistRecords = [
                SELECT Name,Product__r.Name, Quantity__c, Unit_Price__c, UOM__c, Gross_Amount__c , Crate__c
                FROM Picklist__c
                WHERE Delivery_Plan__c = :deliveryPlanId
            ];
		/*if(!picklistRecords.isEmpty()){
            	String filename = picklistRecords[0].Name ;
            	ApexPages.currentPage().getHeaders().put('Content-Disposition', 'attachment; filename="' + filename + '"');
        	} */
            // Fetch the related Delivery Plan
            deliveryPlans = [
                SELECT Driver_Name__c, Driver_Number__c, Vehicle_Number__c, Date__c
                FROM Delivery_Plan__c
                WHERE Id = :deliveryPlanId
            ];   
            if (!deliveryPlans.isEmpty()) {
            // Format the Date__c field in a readable format (e.g., 'MM/dd/yyyy')
            formattedDate = deliveryPlans[0].Date__c.format();
        	}
        } else {
            picklistRecords = new List<Picklist__c>(); 
        }

        // Get logged-in user's ContactId
        User usr = [SELECT ContactId FROM User WHERE Id = :UserInfo.getUserId()];
        
        // Get the Contact record for the logged-in user
        if (usr.ContactId != null) {
        loggedInContact = [SELECT Id, AccountId, Account.Name,Account.Owners_Number__c, Account.Phone, Account.ShippingStreet, Account.ShippingCity, 
                                  Account.ShippingState, Account.ShippingPostalCode, 
                                  Account.ShippingCountry
                           FROM Contact
                           WHERE Id = :usr.ContactId
                           LIMIT 1];
        }
    }
   

    public void setContentDispositionpdf() {
        if(picklistRecords.isEmpty()) return;

       String filename = picklistRecords[0].Name + '.PDF';
            	ApexPages.currentPage().getHeaders().put('Content-Disposition', 'attachment; filename="' + filename + '"');
       
    }
      public void setContentDispositionexcel() {
        if(picklistRecords.isEmpty()) return;

        String filename = picklistRecords[0].Name + '.xls';
       
            ApexPages.currentPage().getHeaders().put('Content-Type', 'application/vnd.ms-excel');
            ApexPages.currentPage().getHeaders().put('Content-Disposition', 'attachment; filename="' + filename + '"');
        }
    
}