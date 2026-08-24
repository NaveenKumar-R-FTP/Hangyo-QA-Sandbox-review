public with sharing class ContentDocumentLinkHandler {
    //This method called after insert from ContentDocumentLinkTrigger 
    public static void handleAfterInsert(List<ContentDocumentLink> contentDocLinks) {
        Set<Id> contentDocIds = new Set<Id>();
        Map<String, String> productDataMap = new Map<String, String>();
        List<Product__c> productList = new List<Product__c>();
        
        // Gather ContentDocumentId and map them to linked Product Ids
        populateContentDocIdsAndProductData(contentDocLinks, contentDocIds, productDataMap);
        
        if (!contentDocIds.isEmpty()) {
            List<ContentDistribution> contentDistributions = createContentDistributions(contentDocIds);
            
            // Insert ContentDistribution records
            insertContentDistributions(contentDistributions);
            
            // Collect ContentDistribution IDs for mapping
            Set<Id> contentDisIds = collectContentDisIds(contentDistributions);
            
            // Update Products with ContentDownloadUrl
            updateProductsWithContentDownloadUrl(contentDisIds, productDataMap, productList);
            
            // Update the Product records
            updateProductRecords(productList);
        }
    }
    //This method is for populateContentDocIdsAndProductData
    private static void populateContentDocIdsAndProductData(List<ContentDocumentLink> contentDocLinks, Set<Id> contentDocIds, Map<String, String> productDataMap) {
        for (ContentDocumentLink linkDoc : contentDocLinks) {
            Id linkedEntityIdData = linkDoc.LinkedEntityId;
            if (linkedEntityIdData != null && linkedEntityIdData.getSObjectType() == Product__c.SObjectType) {
                contentDocIds.add(linkDoc.ContentDocumentId);
                productDataMap.put(linkDoc.ContentDocumentId, linkedEntityIdData);
            }
        }
    }
    //This method is to createContentDistributions
    
    private static List<ContentDistribution> createContentDistributions(Set<Id> contentDocIds) {
        List<ContentDistribution> contentDistributions = new List<ContentDistribution>();
        
        for (ContentVersion cv : [SELECT Id, ContentDocumentId FROM ContentVersion WHERE ContentDocumentId IN :contentDocIds]) {
            ContentDistribution cd = new ContentDistribution();
            cd.Name = cv.ContentDocumentId;
            cd.ContentVersionId = cv.Id;
            cd.PreferencesAllowViewInBrowser = true;
            cd.PreferencesLinkLatestVersion = true;
            cd.PreferencesNotifyOnVisit = false;
            cd.PreferencesPasswordRequired = false;
            cd.PreferencesAllowOriginalDownload = true;
            contentDistributions.add(cd);
        }
        
        return contentDistributions;
    }
    //This method is to insertContentDistributions
    
    private static void insertContentDistributions(List<ContentDistribution> contentDistributions) {
        if (!contentDistributions.isEmpty()) {
            insert contentDistributions;
        }
    }
    //This method is to collectContentDisIds
    
    private static Set<Id> collectContentDisIds(List<ContentDistribution> contentDistributions) {
        Set<Id> contentDisIds = new Set<Id>();
        for (ContentDistribution con : contentDistributions) {
            contentDisIds.add(con.Id);
        }
        return contentDisIds;
    }
    //This method is to updateProductsWithContentDownloadUrl
    
    private static void updateProductsWithContentDownloadUrl(Set<Id> contentDisIds, Map<String, String> productDataMap, List<Product__c> productList) {
        for (ContentDistribution contentDist : [
            SELECT Id, Name, ContentDownloadUrl 
            FROM ContentDistribution 
            WHERE Id IN :contentDisIds
        ]) {
            if (productDataMap.containsKey(contentDist.Name)) {
                productList.add(new Product__c(
                    Id = productDataMap.get(contentDist.Name), 
                    Image_Long__c = contentDist.ContentDownloadUrl
                ));
            }
        }
    }
    //This method is to updateProductRecords
    
    private static void updateProductRecords(List<Product__c> productList) {
        if (!productList.isEmpty()) {
            update productList;
        }
    }
}