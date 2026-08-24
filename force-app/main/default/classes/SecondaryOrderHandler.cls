/*******************************************************************************************************************************************************************
 * Class Name: SecondaryOrderHandler 
 * Description: This apex class is used handle logic required to retrieve,update Order__c Object records of Record Type = Secondary_Order in DMS
 * CHANGE LOG: 
 * -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 * Date      		By           		Description
 * -----------------------------------------------------------------------------------------------------------------------------------------------------------------
 * 27-Dec-2024		Pooja P Bhat		Initial Version
********************************************************************************************************************************************************************/

public with sharing class SecondaryOrderHandler {
    
   public Static String orderFields        =   'Id, Name, AccountId__c, Account__c , EffectiveDate__c,Value_Scheme_Applied__c, Value_Scheme_Discount__c, Type__c, Description__c, Sale_Type__c, Price_Type__c';
    public Static String orderItemFields    =   'Order__c, Ordered_Quantity__c, Product_Price__c, Products__c, Products__r.Name, Total_Amount__c,Products__r.MRP__c,Quantity_Scheme__c, Is_Promotional__c, Parent_Product__c, Discount_Percentage__c';

    /***************************************************************************************************************************************************************
     * Method is used to retrieve Order__c Object record of Record Type = Secondary_Order
     * @param orderNumber: Name
     * @return Order__c Object record of Record Type = Secondary_Order
    ***************************************************************************************************************************************************************/
    @AuraEnabled(cacheable=true)
    public static OrderData fetchOrderAndLineItems(String orderNumber) {
        system.debug('Avengers'+orderNumber);
        OrderData oOrderData = new OrderData();
        try {
            System.debug('orderNumber='+orderNumber);
            oOrderData.order = fetchSecondaryOrder(orderNumber);
            oOrderData.orderItems = oOrderData.order != null ? fectchOrderItems(oOrderData.order.Id) : null;
            System.debug('oOrderData='+oOrderData);
            return oOrderData;     
        } catch (Exception e) {
            System.debug('Exception='+e);
            throw new AuraHandledException('Error while fetching order record: ' + e.getMessage());
        }
    }   //End of getOrderRecord

    public static Order__c fetchSecondaryOrder(String orderNumber) {
        String queryStr                 =   'SELECT ' + orderFields + ' FROM Order__c WHERE RecordType.DeveloperName IN (\'Under_SS_Secondary_Order\', \'Secondary_Order\', \'Counter_Order\') AND Id = :orderNumber LIMIT 1';
        //String queryStr                 =   'SELECT ' + orderFields + ' FROM Order__c WHERE Id = :orderNumber LIMIT 1'; 
        Map<String, Object> bindVarMap  =   new Map<String, Object> {'orderNumber' => orderNumber};
        System.debug('fetchSecondaryOrder queryStr*** ' + queryStr);
        List<Order__c> orderList        =   Utility.soqlQuery(queryStr,bindVarMap,AccessLevel.USER_MODE);
        System.debug('fetchSecondaryOrder order List*** ' + orderList.size() + ' ' + orderList);     
        return orderList.size() == 1 ? orderList[0] : null;
    }   //End of fetchInvoice()
	
    //Added by Supriya to fetch invocie details from Order detail page in DMS 
    @AuraEnabled(cacheable=true)
    public static OrderData ordfetchOrderAndLineItems(String orderNumber) {
        OrderData oOrderData = new OrderData();
        try {
            System.debug('orderNumber='+orderNumber);
            oOrderData.order = ordfetchSecondaryOrder(orderNumber);
            oOrderData.orderItems = oOrderData.order != null ? fectchOrderItems(oOrderData.order.Id) : null;
            System.debug('oOrderData='+oOrderData);
            return oOrderData;     
        } catch (Exception e) {
            System.debug('Exception='+e);
            throw new AuraHandledException('Error while fetching order record: ' + e.getMessage());
        }
    }   //End of getOrderRecord
    
	//Added by Supriya to fetch invocie details from Order detail page in DMS 
    public static Order__c ordfetchSecondaryOrder(String orderNumber) {
        String queryStr                 =   'SELECT ' + orderFields + ' FROM Order__c WHERE RecordType.DeveloperName IN (\'Under_SS_Secondary_Order\', \'Secondary_Order\', \'Counter_Order\') AND Id = :orderNumber LIMIT 1';
        //String queryStr                 =   'SELECT ' + orderFields + ' FROM Order__c WHERE Id = :orderNumber LIMIT 1';
        Map<String, Object> bindVarMap  =   new Map<String, Object> {'orderNumber' => orderNumber};
        System.debug('fetchSecondaryOrder queryStr*** ' + queryStr);
        List<Order__c> orderList        =   Utility.soqlQuery(queryStr,bindVarMap,AccessLevel.USER_MODE);
        System.debug('fetchSecondaryOrder order List*** ' + orderList.size() + ' ' + orderList);     
        return orderList.size() == 1 ? orderList[0] : null;
    }   //End of fetchInvoice()
    public static List<Order_Line_Item__c> fectchOrderItems(Id orderId) {
        String queryStr                 =   'SELECT ' + orderItemFields + ' FROM Order_Line_Item__c WHERE Order__c =: orderId ORDER BY Products__r.Product_Brand__c , Products__r.Name ASC';
        Map<String, Object> bindVarMap  =   new Map<String, Object> {'orderId' => orderId};
        System.debug('fectchOrderItems queryStr*** ' + queryStr);
        List<Order_Line_Item__c> orderItemList  =   Utility.soqlQuery(queryStr,bindVarMap,AccessLevel.USER_MODE);
        System.debug('fectchOrderItems orderItemList*** ' + orderItemList.size() + ' ' + orderItemList);
        return orderItemList.size() > 0 ? orderItemList : null; 
    }   //End of fectchInvLineItems()

    public class OrderData {
        @AuraEnabled
        public Order__c order;
        @AuraEnabled
        public List<Order_Line_Item__c> orderItems;
    }


}   //End of SecondaryOrderHandler