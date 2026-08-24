@IsTest
public class InventoryPriceUpdateBatchTest {
    @testSetup
    
    static void setupData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;
        Product__c prod = new Product__c(
            Name = 'Test Product'
        );
        insert prod;
        Price_Book__c priceBook = new Price_Book__c(
            Name = 'Karnataka'
        );
        insert priceBook;
        Price_Book_Entry__c pbeDirect = new Price_Book_Entry__c(
            Product__c = prod.Id,
            Price_Book__c = priceBook.Id,
            Type__c = 'Direct Distributor',
            PTD__c = 100,
            PTSS__c = 150,
            isActive__c = true
        );
        insert pbeDirect;
        Price_Book_Entry__c pbeSuper = new Price_Book_Entry__c(
            Product__c = prod.Id,
            Price_Book__c = priceBook.Id,
            Type__c = 'Super Stockist',
            PTD__c = 200,
            PTSS__c = 300,
            isActive__c = true
        );
        insert pbeSuper;
        Account distributorSuper = new Account(
            Name = 'Super Distributor',
            Primary_State__c = 'Karnataka',
            Distributor_Type__c = 'Direct Distributor'
        );
        insert distributorSuper;
        Account distributorNormal = new Account(
            Name = 'Normal Distributor',
            Primary_State__c = 'Karnataka',
            Distributor_Type__c = 'Under Super Stockist'
        );
        insert distributorNormal;
        Inventory__c invSuper = new Inventory__c(
            Product__c = prod.Id,
            Distributor_Name__c = distributorSuper.Id,
            Product_Rate__c = null
        );

        Inventory__c invNormal = new Inventory__c(
            Product__c = prod.Id,
            Distributor_Name__c = distributorNormal.Id,
            Product_Rate__c = null
        );

        insert new List<Inventory__c>{ invSuper, invNormal };
    }
    @IsTest
    static void testInventoryPriceUpdateBatch() {
        Test.startTest();
        Database.executeBatch(new InventoryPriceUpdateBatch(), 50);
        Test.stopTest();
        List<Inventory__c> inventories = [
            SELECT Id, Product_Rate__c
            FROM Inventory__c
        ];
        System.assertEquals(2, inventories.size());
        Boolean rateUpdated = false;
        for (Inventory__c inv : inventories) {
            if (inv.Product_Rate__c != null) {
                rateUpdated = true;
            }
        }
        System.assert(rateUpdated, 'Inventory Product Rate should be updated');
    }
}