public with sharing class VisitSummaryPdfRecord {
    @AuraEnabled
    public static List<Visit_Task__c> getBeatsForOrderDate(Date orderDate){
        List<Visit_Task__c> visitTaskList = [SELECT Id , Name , Beat__r.Name FROM Visit_Task__c WHERE Task_Planned_Date__c =: orderDate AND Beat__c != NULL];
        
        return visitTaskList;
    }
    
    @AuraEnabled
    public static String getDistributorName(String beatId){
        String distributorName = [SELECT Id , Distributor_Name__r.Name FROM Beat__c WHERE Id =: beatId and Distributor_Name__c != NULL LIMIT 1].Distributor_Name__c;
        
        return distributorName;
    }
   
    
    @AuraEnabled
    public static List<Order__c> fetchVisitSummaryDetail(String distributorId , Date orderDate){
        if (String.isEmpty(distributorId)){
            throw new AuraHandledException('Distributor ID cannot be null or empty.');
        }
        List<Order__c> orders = [SELECT Id , Name , AccountId__r.Name , Account__r.Name ,  EffectiveDate__c , Value_Scheme_Applied__r.Name , Discount_Amount_Order__c , Total_Order_Value__c , (SELECT Name , Products__r.Name , Product_Price__c , Ordered_Quantity__c , Quantity_Scheme__r.Name , Total_Amount__c FROM Order_Line_Items__r) FROM Order__c WHERE AccountId__c =: distributorId AND EffectiveDate__c =: orderDate AND Record_Type_Name__c = 'Secondary Order' AND Type__c = 'Field Order' ORDER BY Account__r.Name];
        
        return orders;
    }
    
    @AuraEnabled
    public static String generatePdfAndContentUrl(String distributorId, String orderDate) {
        String vfPageUrl = '/apex/VisitSummaryPdfPage?distributorId=' + EncodingUtil.urlEncode(distributorId, 'UTF-8') + '&orderDate=' + EncodingUtil.urlEncode(orderDate, 'UTF-8');
 
        // Generate PDF Blob
        PageReference pdfPage = new PageReference(vfPageUrl);
        Blob pdfBlob;
        if(!Test.isRunningTest()){
            pdfBlob = pdfPage.getContent();
        }
        else{
            pdfBlob = Blob.valueOf('Test Blob Content');
        }
 
        // Create Salesforce File (ContentDocument)
        ContentVersion contentVersion = new ContentVersion();
        contentVersion.Title = 'VisitSummary_' + orderDate + '.pdf';
        contentVersion.PathOnClient = 'VisitSummary.pdf';
        contentVersion.VersionData = pdfBlob;
        contentVersion.IsMajorVersion = true;
        insert contentVersion;
 
        // Get the newly created ContentDocument ID
        //ContentDocument doc = [SELECT Id FROM ContentDocument WHERE LatestPublishedVersionId = :contentVersion.Id LIMIT 1];
 
        // Return the ContentDocument ID (not the URL)
        return contentVersion.Id;
    }
}