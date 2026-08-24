public with sharing class GenerateVisitSummaryPdf {
    public String distributorId { get; set; }
    public Date orderDate { get; set; }
    public String formattedOrderDate { get; set; }
    public String distributorName { get; set; }
    public String distributorPhone { get; set; }
    public List<Order__c> orders { get; set; }
    public GenerateVisitSummaryPdf() {
        distributorId = ApexPages.currentPage().getParameters().get('distributorId');
        String orderDateString = ApexPages.currentPage().getParameters().get('orderDate');
        
        if (String.isNotBlank(orderDateString)) {
            orderDate = Date.valueOf(orderDateString);
            formattedOrderDate = orderDate != null ? orderDate.format() : '';
        }
        //Set<Id> accountId;
        if (String.isNotBlank(distributorId) && orderDate != null) {
            Account acc = [SELECT Id , Name , Distributor__r.Name ,Phone,Owners_Number__c, RecordType.Name FROM Account WHERE Id =: distributorId LIMIT 1];
            distributorName = acc.Name;
            distributorPhone = acc.Owners_Number__c;
            orders = [SELECT Id , Name , AccountId__r.Name , Account__r.Name , Total_Quantity__c , EffectiveDate__c , Value_Scheme_Applied__r.Name , Discount_Amount_Order__c , Total_Order_Value__c , (SELECT Name , Products__r.Name , Product_Price__c , Ordered_Quantity__c , Quantity_Scheme__r.Name , Total_Amount__c FROM Order_Line_Items__r) FROM Order__c WHERE AccountId__c =: distributorId AND EffectiveDate__c =: orderDate AND Record_Type_Name__c = 'Secondary Order' AND Type__c = 'Field Order' ORDER BY Account__r.Name];
        }
    }
}