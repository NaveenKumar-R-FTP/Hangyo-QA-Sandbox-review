public without sharing class CollectionsController { 
    
	//To fetch all retailers tagged to the logged in distributor
    @AuraEnabled(cacheable=true) 
    public static List<Account> getretailersOptions() {
        try{
           List<Account> accList = new List<Account>();
           // Get the current user's details (Distributor_Account__c)
           user usr = [SELECT contactid, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            if(usr.AccountId != NULL){
              accList = [Select Id,Name,Owners_Number__c,RecordType.Name,Distributor_Type__c from Account where Distributor__c =:usr.AccountId OR Super_Stockist_Name__c =:usr.AccountId  ORDER BY RecordType.Name ASC, Name ASC];
            }//added Super_Stockist_Name__c to include under ss collections
           return accList;
        }catch(Exception e){
            throw new AuraHandledException('Error fetching retailers: ' + e.getMessage());
        }
    }
    
    //To fetch all delivered invoices of the logged in distributor related to retailer id
    @AuraEnabled
    public static List<Invoice__c> getDeliveredInvoices(Id retailerId) {
        try{
            // Get the current user's details (Distributor_Account__c)
            user usr = [SELECT contactid, AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            List<Invoice__c> invoicelist = new List<Invoice__c>(); 
            // Get the RecordTypeId for Secondary_Invoice    
            Id secondaryInvoiceRecordTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByName().get('Secondary Invoice').getRecordTypeId();
            Id secondaryInvoiceUSSRecordTypeId = Schema.SObjectType.Invoice__c.getRecordTypeInfosByName().get('Secondary Invoice Under SS').getRecordTypeId();
            if(usr.AccountId != NULL){
            // Fetch delivered invoices for the distributor's account
            invoicelist = [
                SELECT Id, Invoice_Number__c,RecordType.DeveloperName, Retailer_Account__c,Under_SS__c, Under_SS__r.Name,
                Under_SS__r.Total_Available_Credit_Notes__c,Under_SS__r.Total_Credit_Amount__c, Retailer_Account__r.Name,
                Retailer_Account__r.Total_Available_Credit_Notes__c,Retailer_Account__r.Total_Credit_Amount__c,
                Beat__c,Invoice_Amount__c,Total_Quantity__c,Invoice_Date__c,Total_Payable_Balance__c
                FROM Invoice__c 
                WHERE Status__c = 'Delivered' 
                AND Distributor_Account__c = :usr.AccountId
                AND(Retailer_Account__c =: retailerId OR Under_SS__c =:retailerId)
                AND( RecordTypeId = :secondaryInvoiceRecordTypeId OR RecordTypeId = :secondaryInvoiceUSSRecordTypeId)
                AND Total_Payable_Balance__c != 0
                ORDER BY Invoice_Number__c
                
            	];
            }
            return invoicelist;
        }catch(Exception e){
            throw new AuraHandledException('Error fetching invoices: ' + e.getMessage());
        }
    }
    @AuraEnabled
    public static List<Credit_Note__c> validCreditNotes(Id retailerId){
        List<Credit_Note__c> creditNotes = new List<Credit_Note__c>();
        creditNotes = [Select Id,Name,Total_Credit_amount__c,Status__c FROM Credit_Note__c WHERE Retailer__c =: retailerId AND Status__c !='Redeemed' ORDER BY Total_Credit_amount__c];
        return creditNotes;
    } 
    
    /*@AuraEnabled
    public static void saveCollection(List<CollectionDataWrapper> collectionData, String paymentMethod, Date paymentDate) {
        List<Collection__c> collectionsToInsert = new List<Collection__c>();

        // Loop through the collectionData list and create Collection__c records
        for (CollectionDataWrapper data : collectionData) {
            Collection__c newCollection = new Collection__c(
                Invoice__c = data.invoiceId,
                Amount_Collected__c = data.amountCollected,
                Payment_Date__c = paymentDate,
                Payment_Method__c = paymentMethod
            );
            collectionsToInsert.add(newCollection);
        }

        // Insert the collection records
        insert collectionsToInsert;
    }*/
    
   /*@AuraEnabled 
	public static void saveCollection(List<CollectionDataWrapper> collectionData, Id selectedRetailer, String paymentMethod, Date paymentDate, Decimal creditAmountToBeUsed,Map<String, Object> chequeData) {
    List<Credit_Note__c> creditNotes = new List<Credit_Note__c>();
    creditNotes = [Select Id,Name,Total_Credit_amount__c,Status__c FROM Credit_Note__c WHERE Retailer__c =: selectedRetailer AND Status__c !='Redeemed' ORDER BY Total_Credit_amount__c];
    List<Collection__c> collectionsToInsert = new List<Collection__c>();
    Decimal remainingCredit = creditAmountToBeUsed;//var used for Redemption and credit note update
    Decimal remainingCollectionCredit = creditAmountToBeUsed;// var used for updating credits used in the collection record
	List<Redemption__c> redemptionsToInsert = new List<Redemption__c>();
    List<Credit_Note__c> creditNotesToUpdate = new List<Credit_Note__c>();

    // Deduct credit from credit notes
    for (Credit_Note__c creditNote : creditNotes) {
        if (remainingCredit <= 0) {
            break; // Stop if no remaining credit to apply
        }

        Decimal creditUsed = 0;

        if (remainingCredit >= creditNote.Total_Credit_amount__c) {
            // Use the full credit amount from this note
            creditUsed = creditNote.Total_Credit_amount__c;
            remainingCredit -= creditNote.Total_Credit_amount__c;
            creditNote.Total_Credit_amount__c = 0; // Fully redeemed
            creditNote.Status__c = 'Redeemed'; // Mark as redeemed
        } else {
            // Use partial credit amount
            creditUsed = remainingCredit;
            creditNote.Total_Credit_amount__c -= remainingCredit; // Deduct from credit note
            creditNote.Status__c = 'Partially Redeemed';
            remainingCredit = 0; // All credit used
        }

        // Update credit note and create redemption record
        creditNotesToUpdate.add(creditNote);

        Redemption__c redemption = new Redemption__c();
        redemption.Credit_Note__c = creditNote.Id;
        redemption.Redeemed_Amount__c = creditUsed;
        redemption.Redemption_Date__c = paymentDate;
        redemptionsToInsert.add(redemption);
    }

    // Update credit notes and insert redemption records
    if (!creditNotesToUpdate.isEmpty()) {
        update creditNotesToUpdate;
    }
    if (!redemptionsToInsert.isEmpty()) {
        insert redemptionsToInsert;
    }
    // Loop through each invoice in collectionData
    for (CollectionDataWrapper data : collectionData) {
        Collection__c newCollection = new Collection__c();
        newCollection.Invoice__c = data.invoiceId;
        newCollection.Amount_Collected__c = data.amountCollected;
        newCollection.Payment_Date__c = paymentDate;
        newCollection.Payment_Method__c = paymentMethod;
        if(!chequeData.isEmpty() && (String) chequeData.get('chequeNumber')!=''){
            newCollection.Cheque_Number__c = (String) chequeData.get('chequeNumber');
            newCollection.Cheque_Date__c = Date.valueOf((String) chequeData.get('chequeDate'));
            newCollection.Branch_Name__c = (String) chequeData.get('branchName');
            newCollection.Is_Cleared__c = (Boolean) chequeData.get('isChequeCleared');
        }

        // Only apply credit if the credit amount is greater than 0
        if (creditAmountToBeUsed > 0) {
            // If the remaining credit is more than or equal to the payable balance, set the payable balance to 0
            if (remainingCollectionCredit >= data.payableBalance) {
                newCollection.Credit_Amount_Used__c = data.payableBalance;
                remainingCollectionCredit -= data.payableBalance;  // Deduct the full payable balance from remaining credit
                data.payableBalance = 0; // The invoice is fully covered by credit
            } else {
                // If remaining credit is less than the payable balance, deduct the credit amount
                newCollection.Credit_Amount_Used__c = remainingCollectionCredit;
                data.payableBalance -= remainingCollectionCredit;  // Reduce the payable balance by the credit amount
                remainingCollectionCredit = 0; // All credit has been used
            }
        }

        // Add the new collection to the insert list
        collectionsToInsert.add(newCollection);
    }

    // Insert the collections into the database only if there are collections to insert
    if (!collectionsToInsert.isEmpty()) {
        insert collectionsToInsert;
    }
}*/

	@AuraEnabled 
	public static void saveInvoiceCollection(Id invoiceId,Decimal amountCollected, Id selectedRetailer, String paymentMethod, Date paymentDate, Decimal creditAmountToBeUsed,Map<String, Object> chequeData , String narrationData) {
    
    List<Credit_Note__c> creditNotes = new List<Credit_Note__c>();
    creditNotes = [Select Id,Name,Total_Credit_amount__c,Status__c FROM Credit_Note__c WHERE Retailer__c =: selectedRetailer AND Status__c !='Redeemed' ORDER BY Total_Credit_amount__c];
    List<Collection__c> collectionsToInsert = new List<Collection__c>();
    Decimal remainingCredit = creditAmountToBeUsed;//var used for Redemption and credit note update
    Decimal remainingCollectionCredit = creditAmountToBeUsed;// var used for updating credits used in the collection record
	List<Redemption__c> redemptionsToInsert = new List<Redemption__c>();
    List<Credit_Note__c> creditNotesToUpdate = new List<Credit_Note__c>();
    
    Decimal payAbleBalance = [SELECT Id , Total_Payable_Balance__c FROM Invoice__c WHERE Id =: invoiceId].Total_Payable_Balance__c;
    
    // Deduct credit from credit notes
    for (Credit_Note__c creditNote : creditNotes) {
        if (remainingCredit <= 0) {
            break; // Stop if no remaining credit to apply
        }

        Decimal creditUsed = 0;

        if (remainingCredit >= creditNote.Total_Credit_amount__c) {
            // Use the full credit amount from this note
            creditUsed = creditNote.Total_Credit_amount__c;
            remainingCredit -= creditNote.Total_Credit_amount__c;
            creditNote.Total_Credit_amount__c = 0; // Fully redeemed
            creditNote.Status__c = 'Redeemed'; // Mark as redeemed
        } else {
            // Use partial credit amount
            creditUsed = remainingCredit;
            creditNote.Total_Credit_amount__c -= remainingCredit; // Deduct from credit note
            creditNote.Status__c = 'Partially Redeemed';
            remainingCredit = 0; // All credit used
        }

        // Update credit note and create redemption record
        creditNotesToUpdate.add(creditNote);

        Redemption__c redemption = new Redemption__c();
        redemption.Credit_Note__c = creditNote.Id;
        redemption.Redeemed_Amount__c = creditUsed;
        redemption.Redemption_Date__c = paymentDate;
        redemptionsToInsert.add(redemption);
    }

    // Update credit notes and insert redemption records
    if (!creditNotesToUpdate.isEmpty()) {
        update creditNotesToUpdate;
    }
    if (!redemptionsToInsert.isEmpty()) {
        insert redemptionsToInsert;
    }
    // Loop through each invoice in collectionData
    
        Collection__c newCollection = new Collection__c();
        newCollection.Invoice__c = invoiceId;
        newCollection.Amount_Collected__c = amountCollected;
        newCollection.Payment_Date__c = paymentDate;
        newCollection.Payment_Method__c = paymentMethod;
        newCollection.Credit_Amount_Used__c = remainingCollectionCredit;
        newCollection.Narration__c = narrationData;
        newCollection.Remaining_Balance__c = payAbleBalance - (amountCollected + remainingCollectionCredit);
        if(!chequeData.isEmpty() && (String) chequeData.get('chequeNumber')!=''){
            newCollection.Cheque_Number__c = (String) chequeData.get('chequeNumber');
            newCollection.Cheque_Date__c = Date.valueOf((String) chequeData.get('chequeDate'));
            newCollection.Branch_Name__c = (String) chequeData.get('branchName');
            newCollection.Is_Cleared__c = (Boolean) chequeData.get('isChequeCleared');
        }

        // Only apply credit if the credit amount is greater than 0
        /*if (creditAmountToBeUsed > 0) {
            // If the remaining credit is more than or equal to the payable balance, set the payable balance to 0
            if (remainingCollectionCredit >= payableBalance) {
                newCollection.Credit_Amount_Used__c = payableBalance;
                remainingCollectionCredit -= payableBalance;  // Deduct the full payable balance from remaining credit
                payableBalance = 0; // The invoice is fully covered by credit
            } else {
                // If remaining credit is less than the payable balance, deduct the credit amount
                newCollection.Credit_Amount_Used__c = remainingCollectionCredit;
                payableBalance -= remainingCollectionCredit;  // Reduce the payable balance by the credit amount
                remainingCollectionCredit = 0; // All credit has been used
            }
        }*/

        // Add the new collection to the insert list
        collectionsToInsert.add(newCollection);
    

    // Insert the collections into the database only if there are collections to insert
    if (!collectionsToInsert.isEmpty()) {
        insert collectionsToInsert;
    }
}
 	@AuraEnabled(cacheable=true)
    public static Invoice__c getInvoiceStatus(Id invoiceId) {
        try {
            // Query the invoice status
            Invoice__c invoice = [
                SELECT Id,Status__c, Invoice_Number__c, Retailer_Account__c, Retailer_Account__r.Name,
                Retailer_Account__r.Total_Available_Credit_Notes__c,Retailer_Account__r.Total_Credit_Amount__c,
                Beat__c,Invoice_Amount__c,Total_Quantity__c,Invoice_Date__c,Total_Payable_Balance__c, Under_SS__c, Under_SS__r.Name,
                Under_SS__r.Total_Available_Credit_Notes__c,Under_SS__r.Total_Credit_Amount__c,RecordType.DeveloperName
                FROM Invoice__c 
                WHERE Id = :invoiceId
                LIMIT 1
            ];
            return invoice;
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching invoice status: ' + e.getMessage());
        }
    }
    
    public class CollectionDataWrapper {
        @AuraEnabled public String invoiceId { get; set; }
        @AuraEnabled public Decimal amountCollected { get; set; }
        @AuraEnabled public Decimal payableBalance { get; set; }
        
    }

}