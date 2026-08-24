@isTest
public class PicklistPDFControllerTest {

    @isTest
    static void testPicklistPDFController() {
        // Create test data
        Account account = new Account(Name = 'Test Account', Phone = '1234567890', ShippingStreet = '123 Test St', 
                                      ShippingCity = 'Test City', ShippingState = 'TS', ShippingPostalCode = '12345', 
                                      ShippingCountry = 'Test Country');
        insert account;

        Contact contact = new Contact(FirstName = 'Test', LastName = 'User', AccountId = account.Id);
        insert contact;

        User testUser = new User(
            FirstName = 'Test',
            LastName = 'User',
            Email = 'testuser@example.com',
            Username = 'testusermystery@example.com.salesforce',
            Alias = 'testusr',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            ContactId = contact.Id,
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'DMS Partner Community Custom' LIMIT 1].Id,
            LanguageLocaleKey = 'en_US',
            Primary_Distributor__c = true
        );
        insert testUser;
		Id productRecordTypeId = [ 
            SELECT Id FROM RecordType 
            WHERE DeveloperName = 'Product' AND SObjectType = 'Product__c' 
            LIMIT 1 
        ].Id;

        Product__c testProduct = new Product__c(
            Name = 'Test Product',
            IsActive__c = true,
            Primary_Product__c = true,
            RecordTypeId = productRecordTypeId,
            Rate_Value__c = 100,
            Unit_of_Measure__c = 'kg',
            Product_Brand__c = 'TestBrand',
            Image__c = 'test_image1.jpg,test_image2.jpg'
        );
        insert testProduct;
        System.runAs(testUser) {
        // Create Delivery Plan record
        Delivery_Plan__c deliveryPlan = new Delivery_Plan__c(
            Driver_Name__c = 'John Doe', Driver_Number__c = '123', Vehicle_Number__c = 'XYZ-456', Date__c = Date.today());
        insert deliveryPlan;

        // Create Picklist record
        Picklist__c picklistRecord = new Picklist__c(
            Delivery_Plan__c = deliveryPlan.Id, Product__c=testProduct.Id, Quantity__c = 10, Unit_Price__c = 5.0, 
            UOM__c = 'kg', Gross_Amount__c = 50.0);
        insert picklistRecord;

        // Set up the page parameters
        Test.startTest();
        
        // Run as the created user
        
            ApexPages.currentPage().getParameters().put('id', deliveryPlan.Id);

            // Instantiate the controller
            PicklistPDFController controller = new PicklistPDFController();
            controller.setContentDispositionpdf();
            controller.setContentDispositionexcel();

            // Assertions
            System.assertNotEquals(controller.picklistRecords.size(), 0, 'Picklist records should be fetched.');
            System.assertEquals(controller.deliveryPlans.size(), 1, 'One delivery plan should be fetched.');
            System.assertEquals(controller.formattedDate, Date.today().format(), 'Date should be formatted correctly.');
            System.assertNotEquals(controller.loggedInContact, null, 'Logged-in contact should be fetched.');
            //System.assertEquals(controller.loggedInContact.Account.Name, 'Test Account', 'Account name should match.');
        }
        
        Test.stopTest();
    }
}