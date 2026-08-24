/**
* Class Name  : EWayBillExcelController
* Test Class  : EWayBillExcelControllerTest
* Author      : Mirza
* CreatedDate : 30-04-25
* Description : Controller class of vf page (EWayBillExcel) to fetch invoice and invoice line item details to generate E-way bill for the delivery plan record
* */
public class EWayBillExcelController {
    
    public Id deliveryPlanId { get; set; } 
    public List<Delivery_Plan_Items__c> deliveryPlanItemList {get; set;}
    public List<Invoice__c> invoiceList {get; set;}
    public Date currentDate { get; set; }
    
    public EWayBillExcelController(){
        deliveryPlanId = ApexPages.currentPage().getParameters().get('Id');  //To store delivery plan record Id
        Set<String> invoiceId = new Set<String>();                           //Set to store invoice Id tagged to the delivery plan item
        String deliveryPlanName;
        
        if(deliveryPlanId != Null){
            deliveryPlanItemList = [SELECT Id , Name , Invoices__c , Delivery_Plan__c , Delivery_Plan__r.Name FROM Delivery_Plan_Items__c WHERE Delivery_Plan__c =: deliveryPlanId];
            for(Delivery_Plan_Items__c deliveryPlanItemRecord : deliveryPlanItemList){
                invoiceId.add(deliveryPlanItemRecord.Invoices__c);
                deliveryPlanName = deliveryPlanItemRecord.Delivery_Plan__r.Name;
            }
        }
        
        if(invoiceId.size()>0){
            invoiceList = fetchInvoiceData(invoiceId);
            currentDate = Date.today();
            String filename = deliveryPlanName + '_EWayBill.xls';
            ApexPages.currentPage().getHeaders().put('Content-Disposition', 'attachment; filename="' + filename + '"');
        }
    }
    
    //Method to fetch invoice and invoice line item details
    public List<Invoice__c> fetchInvoiceData(Set<String> invoiceIdSet) {
        return [
            SELECT Name, Invoice_Date__c, RecordType.DeveloperName,
                   Distributor_Account__r.Name,
                   Distributor_Account__r.GSTIN__c,
                   Distributor_Account__r.BillingStreet,
                   Distributor_Account__r.BillingCity,
                   Distributor_Account__r.BillingPostalCode,
                   Distributor_Account__r.BillingState,
                   Distributor_Account__r.ShippingState,
                   Retailer_Account__r.Name,
                   Retailer_Account__r.GSTIN__c,
                   Retailer_Account__r.BillingStreet,
                   Retailer_Account__r.BillingCity,
                   Retailer_Account__r.BillingPostalCode,
                   Retailer_Account__r.BillingState,
                   Retailer_Account__r.ShippingState,
                   Under_SS__r.Name,
                   Under_SS__r.GSTIN__c,
                   Under_SS__r.BillingStreet,
                   Under_SS__r.BillingCity,
                   Under_SS__r.BillingPostalCode,
                   Under_SS__r.BillingState,
                   Under_SS__r.ShippingState,
                   (SELECT Product__r.Name, Product__r.HSN__c, Product__r.Unit_of_Measure__c, Quantity__c,
                           Price__c, CGST_Amount__c, SGST_Amount__c,
                           IGST_Amount__c, Total_Amount__c
                    FROM Invoice_Line_Items__r)
            FROM Invoice__c
            WHERE Id IN: invoiceIdSet
            ORDER BY CreatedDate DESC
        ];
    }
}