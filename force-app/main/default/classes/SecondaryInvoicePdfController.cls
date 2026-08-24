/*******************************************************************************************************************************************************************
 * Class Name: SecondaryInvoicePdfController 
 * Description: This apex class is used to Generate Secondary Invoice PDF. It accepts URL Parameters and generate PDF.
 *              /apex/SecondaryInvoicePdf?invoiceId={SecondaryInvoiceId}&distributorId={DistributorId}&retailerId={RetailerAccountId}
 *              Note: Class is run in System Context, to avoid sharing issue.
 *                  
 * CHANGE LOG: 
 * -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 * Date             By                  Description
 * -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 * 03-Jan-2025      Pooja P Bhat        Initial Version
********************************************************************************************************************************************************************/

public class SecondaryInvoicePdfController {
    public User dmsUserInfo { get; set; }
    public Account retailerInfo { get; set; }
    public Account underSSInfo { get; set; }
    public Invoice__c invoiceInfo { get; set; }
    public List<Invoice_Line_Item__c> invLineItem { get; set; }
    public Integer totalUnit { get; set; }
    public String freeOfferMessage { get; set; } // Modern Trade free-goods scheme message, shown next to CGST
    public List<AppliedSchemeDisplay> appliedQuantityDiscountSchemes { get; set; }

    /***************************************************************************************************************************************************************
    * Constructor gets the URL parameters supplied and fetches the Invoice, Distirbutor and Retailer Information and helps with the PDF Generation
    * @param invoiceId: Invoice Id
    * @param distributorId: Distributor Id
    * @param retailerId: Retailer Id
    * @return PageReference
    ***************************************************************************************************************************************************************/
    public SecondaryInvoicePdfController() {
        String invoiceId       =    String.escapeSingleQuotes(ApexPages.currentPage().getParameters().get('invoiceId'));
        String distributorId   =    String.escapeSingleQuotes(ApexPages.currentPage().getParameters().get('distributorId'));
        String retailerId      =    String.escapeSingleQuotes(ApexPages.currentPage().getParameters().get('retailerId'));
        invoiceInfo = SecondaryInvoiceHandler.fetchInvoice(invoiceId);
        invLineItem = SecondaryInvoiceHandler.fetchInvLineItems(new Set<Id>{invoiceId});
        //dmsUserInfo = DmsUserProfile.fetchDMSUser(distributorId);
        Id userId                       =   UserInfo.getUserId();
        User loggedInUser = [SELECT Id, AccountId FROM User WHERE Id = :UserInfo.getUserId()];
    
        // Check if logged-in user has an AccountId
        if (loggedInUser.AccountId == null) {
            System.debug('No AccountId found for the logged-in user.');
            // Exit if there's no AccountId
        }
        dmsUserInfo = [Select Id, Name, CompanyName, Phone, MobilePhone, Email, FullPhotoUrl, SmallPhotoUrl, MediumPhotoUrl,GSTIN__c, PAN_Number__c, Invoice_Number_Prefix__c, Invoice_Start_Number__c, State, Notes__c,Terms_and_Conditions__c, Contact.AccountId,Contact.Account.Name,UPI_ID__c,UPI_QR_CODE__c,Bank_Name__c,Bank_Account_Number__c,IFSC_Code__c FROM User WHERE AccountId=:loggedInUser.AccountId AND Primary_Distributor__c = true LIMIT 1];
        Id underSSId = [Select Under_SS__c from Invoice__c where Id =: invoiceId].Under_SS__c;
        retailerInfo = RetailerAccountHandler.getRetailerAccount(retailerId);
        if(underSSId != null){ 
        	underSSInfo = [Select Name,Phone,Primary_Address_1__c,GSTIN__c,FSSAI__c,Ship_To_Address_1__c,BillingStreet, BillingCity,BillingState,BillingPostalCode,BillingCountry,Owners_Number__c FROM Account where Id =:underSSId];
        }
        totalUnit = 0;
        for(Invoice_Line_Item__c oILI : invLineItem) {                  //To sum up total PIECES across Invoice Line Items
            // Quantity__c is in whatever unit was ordered (e.g. boxes), not pieces.
            // Product__r.Per_Pieces__c is "pieces per box" for that product — multiply
            // through so this total is always in actual pieces, e.g. 3 boxes at
            // 12/13/15 pieces each = 40, not 3. Falls back to 1 if Per_Pieces__c is
            // missing/zero, so this can't break for products without it configured.
            Decimal qty = oILI.Quantity__c != null ? oILI.Quantity__c : 0;
            Decimal perPieces = (oILI.Product__r != null && oILI.Product__r.Per_Pieces__c != null && oILI.Product__r.Per_Pieces__c > 0)
                                ? oILI.Product__r.Per_Pieces__c : 1;
            totalUnit = totalUnit + Integer.valueOf(qty * perPieces);
        }

        // Modern Trade free-goods scheme — bold message shown next to CGST.
        // NOTE: the /apex/SecondaryInvoicePdf Visualforce page this controller backs isn't
        // present in this source checkout, so freeOfferMessage still needs to be added to
        // that page's markup directly in Setup (same {!freeOfferMessage}, rendered=
        // {!NOT(ISBLANK(freeOfferMessage))} pattern used on CounterInvoicePdf.page /
        // SecondaryInvoiceDownloader.page) before it will actually show up here.
        freeOfferMessage = ModernTradeSchemeService.getFreeOfferMessage(invLineItem);

        // Purchase Quantity Discount scheme(s) applied — shown just above Taxable Value
        // on the page. invLineItem already has Quantity_Scheme_Applied__r.Name/
        // Discount_Percentage__c/Type__c via SecondaryInvoiceHandler.invoiceItemFields.
        appliedQuantityDiscountSchemes = SchemeEvaluationService.getAppliedQuantityDiscountSchemes(invLineItem);
    }   //End of SecondaryInvoicePdfController()

    /***************************************************************************************************************************************************************
     * Method is used to create and save Invoice details into file by creating Content Document, Content Version and Content Document Link
     * The file is attached under the respective Secondary Invoice Record
     * @param oInvoice: Invoice Record of type Secondary_Invoice
     * @param distributorId: Account Id of Distributor
     * @param retailerId: Account Id of Retailer
     * @return ContentVersionid
    ***************************************************************************************************************************************************************/
    @AuraEnabled
    public static String generatePDF(Invoice__c oInvoice, Id distributorId, Id retailerId){
        try {
            //Set the Page Parameters
            Pagereference page = new PageReference('/apex/SecondaryInvoicePdf');
            page.getParameters().put('invoiceId', oInvoice.Id);
            page.getParameters().put('distributorId', distributorId);
            page.getParameters().put('retailerId', retailerId); // System.debug('*** page*** ' + page);
            //Delete all existing Content Documents associated with the Invoice record
            list<ContentDocument> lstCntDocsToDelete = new list<ContentDocument>();
            for(ContentDocumentLink iterator : [SELECT ContentDocumentId FROM ContentDocumentLink WHERE LinkedEntityId =:oInvoice.Id]) {
                lstCntDocsToDelete.add(new ContentDocument(Id = iterator.ContentDocumentId));
            }
            if(lstCntDocsToDelete.isEmpty() == false) {
                Database.delete(lstCntDocsToDelete, false);
                Database.emptyRecycleBin(lstCntDocsToDelete);
            }
            //Create new ContentVersion and ContentDocument
            ContentVersion oCV = new ContentVersion();
            oCV.Title = oInvoice.Invoice_Number__c;
            oCV.PathOnClient = oCV.Title + '.pdf';
            if (Test.isRunningTest()) {
            oCV.VersionData = Blob.valueOf('Mock PDF Content');
            }else{
            oCV.VersionData =  page.getContentaspdf();
            }
            oCV.ContentLocation = 'S';
            insert oCV; // System.debug('*** oCV*** ' + oCV);
            //Fetching the ContentDocumentId From newly inserted ContenVersion
            Id contentDocId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id=:oCV.Id].ContentDocumentId; 
            System.debug('***contentDocId *** ' + contentDocId);
            //Creating ContentDocumentLink, i.e Attaching the Generated PDF File to the Invoice Records
            ContentDocumentLink oLink = new ContentDocumentLink(
                ContentDocumentId = contentDocId,
                LinkedEntityId = oInvoice.Id,
                Visibility = 'AllUsers',
                ShareType = 'V'
            );
            insert oLink; 
            System.debug('***oLink *** ' + oLink);
            return oCV.Id;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }   //End of generatePDF()

} //End of class SecondaryInvoicePdfController