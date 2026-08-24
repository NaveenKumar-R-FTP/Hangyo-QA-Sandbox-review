public without sharing class SalesOrderAPI {


    public static void pushPrimaryOrderstoSAP(Id orderId) {
        System.debug('orderId======'+orderId);
        List<User> curUserList = [SELECT Contact.AccountId, Contact.Account.Disable_API__c, 
                                        Contact.Account.RecordType.DeveloperName 
                                FROM User 
                                WHERE Id = :UserInfo.getUserId()];
        System.debug('*****curUserList******'+curUserList);
        System.debug('*******curUserList disable*****'+curUserList[0].Contact.Account.Disable_API__c);
        if(curUserList!=null && !curUserList[0].Contact.Account.Disable_API__c){
            sendPrimaryOrderstoSAP(orderId);
        }
                
    }

    @future (callout=true)
    public static void sendPrimaryOrderstoSAP(Id orderId) {
        if(System.label.Run_Sales_Order_API == 'True' || Test.isRunningTest()){
            pushOrderandOrderItems(orderId);
        }
        
    }

    public static void pushOrderandOrderItems(Id orderId){

        if(orderId==null){
            return;
        }
        Integration_Log__c log = new Integration_Log__c(Name='SalesOrderAPI',Status__c='Success',Record_Id__c=orderId);
        
        try{
            
            Order__c ord = new Order__c();
            if (Schema.sObjectType.Order__c.isAccessible() && Schema.sObjectType.Order_Line_Item__c.isAccessible()) {
                ord = [
                    SELECT Id, EffectiveDate__c, Name, AccountId__c, 
                        AccountId__r.Sales_Office__c, AccountId__r.Code__c,AccountId__r.Partner_Code__c, 
                        AccountId__r.Sales_Office__r.Sales_Organization__c, 
                        (SELECT Id, Products__c, Ordered_Quantity__c, 
                                Products__r.Product_Code__c, Products__r.Unit_of_Measure__c 
                            FROM Order_Line_Items__r WHERE Products__c != null) 
                    FROM Order__c 
                    WHERE Id = :orderId AND AccountId__c != null 
                    LIMIT 1
                ];
            }
            
            // Prepare the request body as before
            String reqJson = prepareRequestBody(ord);
            log.Request__c=reqJson;
            if(String.isNotBlank(reqJson)){
                reqJson = reqJson.replace('toItem', 'to_Item');
                System.debug('******reqJs2*****'+reqJson);
                HttpRequest req = new HttpRequest();
        
                // Use the Named Credential in the endpoint (no need to include authentication info)
                req.setEndpoint('callout:HangyoNamedCredential');
                req.setMethod('POST');
                req.setTimeout(20000);
                req.setBody(reqJson);

                // Send the HTTP request
                Http http = new Http();
                HTTPResponse res = http.send(req);
                
                if(res!=null){
                    processResponse(ord,res);
                    log.Response__c  = res.getBody();
                }
                
            }
        } catch(Exception excp){
            log.Error_Message__c    =   excp.getMessage();
            log.Status__c           =   'Fail';
            
        }
        
        Insert log;
        
    }

    static string prepareRequestBody(Order__c ord){
        RequestJSON reqJs = new RequestJSON();
            reqJs.SalesOrderType = 'OR';
            reqJs.SoldToParty = String.IsBlank(ord.AccountId__r.Code__c)?'':ord.AccountId__r.Code__c;
            reqJs.ShipToParty = String.IsBlank(ord.AccountId__r.Partner_Code__c)?'':ord.AccountId__r.Partner_Code__c;
            reqJs.salesOrderDate = '';
            if(ord.EffectiveDate__c !=null){
                reqJs.salesOrderDate = ord.EffectiveDate__c.year()+'-'+String.valueOf(Ord.EffectiveDate__c.month()).leftPad(2,'0')+'-'+String.valueOf(Ord.EffectiveDate__c.Day()).leftPad(2,'0')+'T00:00:00';
            }
            
            if(ord.AccountId__r.Sales_Office__c != null ){
                reqJs.SalesOrganization = String.IsBlank(ord.AccountId__r.Sales_Office__r.Sales_Organization__c)?'':ord.AccountId__r.Sales_Office__r.Sales_Organization__c;
            }
            reqJs.PurchaseOrderByCustomer = ord.Name;
            reqJs.toItem = new List<Item>();
            integer temp = 1;
            for(Order_Line_Item__c oItem:ord.Order_Line_Items__r){
                Item each = new Item();
                    each.SalesOrderItem = string.valueOf(temp*10);
                    each.Material = String.isBlank(oItem.Products__r.Product_Code__c)?'':oItem.Products__r.Product_Code__c;
                    each.RequestedQuantity = string.valueOf(oItem.Ordered_Quantity__c);
                    each.RequestedQuantityUnit= String.isBlank(oItem.Products__r.Unit_of_Measure__c)?'EA':oItem.Products__r.Unit_of_Measure__c;

                reqJs.toItem.add(each);
                temp++;

            }
        System.debug('******reqJs*****'+reqJs);
        return JSON.serialize(reqJs);
    }
    static void processResponse(order__C ord,HTTPResponse res){
        string resStr = res.getBody();
        OrderResponse respWrap = (OrderResponse)System.JSON.deserialize(resStr, OrderResponse.class);
        System.debug('processResponse===='+respWrap);
        list<Order__c> ordList = new List<Order__C>();
        if(ord!=null && respWrap != null && respWrap.data != null ){
            if(String.isNotBlank(respWrap.data.sap_reference)){
                ord.SAP_Reference_Number__c =   respWrap.data.sap_reference;
            }            
            ord.SAP_Response__c         =   respWrap.data.message;
            ord.SAP_Status__c           =   respWrap.data.status;

            ordList.add(ord);
        }

        System.debug('*******ordList****'+ordList);
        if(!ordList.isEmpty()){
            Update ordList;
        }
    }
    public class RequestJSON{
        public String SalesOrderType;	//OR
        public String SalesOrganization;	//1000
        public String SoldToParty;	//1011000021
        public string ShipToParty;
        public String PurchaseOrderByCustomer;	//test004
        public String SalesOrderDate;
        public List<Item> toItem;
    }

    class Item {
        public String SalesOrderItem;	//10        
        public String Material;	//5300010
        public String RequestedQuantity;	//1.000
        public String RequestedQuantityUnit;	//EA
    }

    public class OrderResponse{
        public response data;      
    }
    
	class response {
		public String ord_reference;	//O-0303
		public String sap_reference;	//
		public String status;	//Sales order creation failed
		public String message;	//Purchase order number in document number: 1179 already exists
	}
}