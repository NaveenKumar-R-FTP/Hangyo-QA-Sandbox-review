@isTest
private class ModernTradeSchemeServiceTest {

    @isTest
    static void testNullAndEmptyInputsReturnNoMessage() {
        System.assertEquals(null, ModernTradeSchemeService.getFreeOfferMessage(null));
        System.assertEquals(null, ModernTradeSchemeService.getFreeOfferMessage(new List<Invoice_Line_Item__c>()));
        System.assertEquals(0, ModernTradeSchemeService.getQualifyingQuantity(null));
    }

    @isTest
    static void testQualifyingAndNonQualifyingProducts() {
        Id productRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Product__c' AND DeveloperName = 'Product' LIMIT 1].Id;

        // Injected directly rather than depending on real Modern_Trade_Scheme_Product__mdt
        // records existing in this org — see @TestVisible note on the cache field.
        ModernTradeSchemeService.qualifyingSapCodesCache = new Set<String>{ 'TEST-QUALIFY-1' };

        Product__c qualifyingProduct = new Product__c(
            Name = 'Test Qualifying Modern Trade Product',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 100,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = 'NOTAMATCH',
            Category_Name__c = 'Test Category',
            Product_Code__c = 'TEST-QUALIFY-1'
        );
        Product__c nonQualifyingProduct = new Product__c(
            Name = 'Test Non-Qualifying Product',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 50,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = 'ALSO-NOT-A-MATCH',
            Category_Name__c = 'Test Category',
            Product_Code__c = '9999999'
        );
        insert new List<Product__c>{ qualifyingProduct, nonQualifyingProduct };

        // In-memory line items — no Invoice__c parent needed since the service only reads
        // Quantity__c and Product__r.Product_Code__c / Category_Code__c off what's passed
        // in. Product__r is populated directly here since these lines are never inserted
        // (Apex allows assigning a parent relationship field directly on an in-memory
        // SObject, it just can't be persisted that way via DML).
        List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();
        Invoice_Line_Item__c qualifyingLine = new Invoice_Line_Item__c(Quantity__c = 10);
        qualifyingLine.Product__r = qualifyingProduct;
        Invoice_Line_Item__c nonQualifyingLine = new Invoice_Line_Item__c(Quantity__c = 25);
        nonQualifyingLine.Product__r = nonQualifyingProduct;
        lineItems.add(qualifyingLine);
        lineItems.add(nonQualifyingLine);

        Decimal qualifyingQty = ModernTradeSchemeService.getQualifyingQuantity(lineItems);
        System.assertEquals(10, qualifyingQty, 'Only the qualifying line\'s quantity should count.');

        String message = ModernTradeSchemeService.getFreeOfferMessage(lineItems);
        System.assert(message != null, 'A qualifying product should produce a Free Offer message.');
        System.assert(message.contains('10 pieces'), '1:1 rule - 10 qualifying pieces = 10 free pieces. Message was: ' + message);
        System.assert(message.startsWith('Free Offer:'));
    }

    @isTest
    static void testQuantityIsConvertedToPiecesUsingPerPieces() {
        Id productRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Product__c' AND DeveloperName = 'Product' LIMIT 1].Id;

        ModernTradeSchemeService.qualifyingSapCodesCache = new Set<String>{ 'TEST-QUALIFY-2' };

        // 1 box = 12 pieces. Ordering 2 boxes should count as 24 pieces toward the
        // scheme, not 2 — this is the exact bug being guarded against here.
        Product__c qualifyingProduct = new Product__c(
            Name = 'Test Qualifying Product With Per Pieces',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 100,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = 'NOTAMATCH2',
            Category_Name__c = 'Test Category',
            Product_Code__c = 'TEST-QUALIFY-2',
            Per_Pieces__c = 12
        );
        insert qualifyingProduct;

        Invoice_Line_Item__c line = new Invoice_Line_Item__c(Quantity__c = 2);
        line.Product__r = qualifyingProduct;

        Decimal qualifyingQty = ModernTradeSchemeService.getQualifyingQuantity(new List<Invoice_Line_Item__c>{ line });
        System.assertEquals(24, qualifyingQty, '2 boxes at 12 pieces each should be 24 qualifying pieces, not 2.');

        String message = ModernTradeSchemeService.getFreeOfferMessage(new List<Invoice_Line_Item__c>{ line });
        System.assert(message.contains('24 pieces'), '1:1 rule - 24 qualifying pieces = 24 free pieces. Message was: ' + message);
    }

    @isTest
    static void testMissingPerPiecesFallsBackToRawQuantity() {
        Id productRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Product__c' AND DeveloperName = 'Product' LIMIT 1].Id;

        ModernTradeSchemeService.qualifyingSapCodesCache = new Set<String>{ 'TEST-QUALIFY-3' };

        // No Per_Pieces__c set at all — should behave exactly like before (treat
        // Quantity__c as already being in pieces), so this can't break for products
        // that haven't had Per_Pieces__c configured yet.
        Product__c qualifyingProduct = new Product__c(
            Name = 'Test Qualifying Product No Per Pieces',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 100,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = 'NOTAMATCH3',
            Category_Name__c = 'Test Category',
            Product_Code__c = 'TEST-QUALIFY-3'
        );
        insert qualifyingProduct;

        Invoice_Line_Item__c line = new Invoice_Line_Item__c(Quantity__c = 10);
        line.Product__r = qualifyingProduct;

        Decimal qualifyingQty = ModernTradeSchemeService.getQualifyingQuantity(new List<Invoice_Line_Item__c>{ line });
        System.assertEquals(10, qualifyingQty, 'With no Per_Pieces__c set, quantity should be used as-is.');
    }

    @isTest
    static void testNoQualifyingProductsReturnsNoMessage() {
        Id productRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Product__c' AND DeveloperName = 'Product' LIMIT 1].Id;
        Product__c nonQualifyingProduct = new Product__c(
            Name = 'Test Non-Qualifying Product 2',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 50,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = 'NOPE',
            Category_Name__c = 'Test Category',
            Product_Code__c = '0000000'
        );
        insert nonQualifyingProduct;

        Invoice_Line_Item__c line = new Invoice_Line_Item__c(Quantity__c = 100);
        line.Product__r = nonQualifyingProduct;

        String message = ModernTradeSchemeService.getFreeOfferMessage(new List<Invoice_Line_Item__c>{ line });
        System.assertEquals(null, message);
    }

    // ── Coverage for getFreeOfferMessageForProducts(), the LWC-facing entry point
    // used by every screen's live cart recalculation (not just the PDF/backend path
    // exercised by the tests above) ──

    @isTest
    static void testGetFreeOfferMessageForProductsBlankOrEmptyInputReturnsNull() {
        System.assertEquals(null, ModernTradeSchemeService.getFreeOfferMessageForProducts(null));
        System.assertEquals(null, ModernTradeSchemeService.getFreeOfferMessageForProducts(''));
        System.assertEquals(null, ModernTradeSchemeService.getFreeOfferMessageForProducts('[]'));
    }

    @isTest
    static void testGetFreeOfferMessageForProductsWithNullProductIdReturnsNull() {
        String json = '[{"productId":null,"quantity":5}]';
        System.assertEquals(null, ModernTradeSchemeService.getFreeOfferMessageForProducts(json));
    }

    @isTest
    static void testGetFreeOfferMessageForProductsResolvesQualifyingProduct() {
        Id productRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Product__c' AND DeveloperName = 'Product' LIMIT 1].Id;
        ModernTradeSchemeService.qualifyingSapCodesCache = new Set<String>{ 'TEST-QUALIFY-4' };

        Product__c qualifyingProduct = new Product__c(
            Name = 'Test Qualifying Product For LWC Entry Point',
            RecordTypeId = productRT,
            IsActive__c = true,
            Secondary_Product__c = true,
            MRP__c = 100,
            Image_Long__c = 'https://example.com/img.png',
            Unit_of_Measure__c = 'EA',
            Product_Brand__c = 'Test Brand',
            Category_Code__c = 'NOTAMATCH4',
            Category_Name__c = 'Test Category',
            Product_Code__c = 'TEST-QUALIFY-4',
            Per_Pieces__c = 10
        );
        insert qualifyingProduct;

        // Includes one item with a null productId too, to also cover the pseudo-line-item
        // loop's own null/not-found guard (not just the earlier productIds-building guard).
        String productQtyJson = '[{"productId":"' + qualifyingProduct.Id + '","quantity":3},{"productId":null,"quantity":5}]';

        String message = ModernTradeSchemeService.getFreeOfferMessageForProducts(productQtyJson);
        System.assert(message != null, 'Should produce a message for the qualifying product.');
        System.assert(message.contains('30 pieces'), '3 units at 10 pieces each = 30 qualifying pieces. Message was: ' + message);
    }
}