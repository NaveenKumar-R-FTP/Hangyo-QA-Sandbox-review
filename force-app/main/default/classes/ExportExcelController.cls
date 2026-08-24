public class ExportExcelController {
    public Id orderId { get; set; }
    public List<Order__c> orders { get; set; }
    public List<Order_Line_Item__c> orderLineItems { get; set; }
    
    public ExportExcelController(){
        //orderId ='a0HH10000060EWKMA2';
        orderId = ApexPages.currentPage().getParameters().get('Id');
        System.debug('orderId=> ' + orderId);
        if(orderId != null){
            orders = [SELECT Id, Name, EffectiveDate__c, AccountId__r.Name, Total_Order_Value__c , Type__c FROM Order__c WHERE Id =: orderId LIMIT 1];
            orderLineItems = [SELECT Id,Name, Products__r.Name, Product_Price__c , Ordered_Quantity__c, Total_Amount__c FROM Order_Line_Item__c WHERE Order__c = :orderId];
        }
        // Dynamically set the filename based on the order's name
        String filename = orders[0].Name + '_OrderDetails.xls';
        ApexPages.currentPage().getHeaders().put('Content-Disposition', 'attachment; filename="' + filename + '"');
    }
}