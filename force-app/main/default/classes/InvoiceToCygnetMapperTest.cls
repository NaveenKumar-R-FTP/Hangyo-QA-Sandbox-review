@IsTest
private class InvoiceToCygnetMapperTest {
    @TestSetup
    static void setupData() {
        CygnetIntegrationTestDataFactory.insertCygnetHierarchySettings();
    }

    @IsTest
    static void testBuildEInvoiceSaveBody_SecondaryInvoice_ContainsSellerBuyer() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + Product__c + Invoice_Line_Item__c');

        Test.startTest();
        String json = InvoiceToCygnetMapper.buildEInvoiceSaveBody(invId);
        Test.stopTest();

        System.assert(json.contains('SellerDtls'), 'Expected SellerDtls in payload');
        System.assert(json.contains('BuyerDtls'), 'Expected BuyerDtls in payload');
        System.assert(json.contains('ItemList'), 'Expected ItemList in payload');
    }

    @IsTest
    static void testBuildEInvoicePdfCriterias_ReturnsLocationJson() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + related objects');

        Test.startTest();
        String json = InvoiceToCygnetMapper.buildEInvoicePdfCriterias(invId);
        Test.stopTest();

        System.assert(json.contains('locationGstin'), 'Expected locationGstin');
        System.assert(json.contains('criterias'), 'Expected criterias wrapper');
    }

    @IsTest
    static void testBuildEwayBillByIrnBody_ContainsIrnAndPartB() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + related objects');

        SObject inv = new Invoice__c(Id = invId);
        inv.put('IRN_Number__c', CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX);
        inv.put('Vehicle_Number__c', 'KA01AB1234');
        inv.put('Transport_Mode__c', 'Road');
        inv.put('Transport_Distance__c', 50);
        update inv;

        Test.startTest();
        String json = InvoiceToCygnetMapper.buildEwayBillByIrnBody(invId);
        Test.stopTest();

        System.assert(json.contains('PartBDtls'), 'Expected PartBDtls');
        System.assert(json.contains(CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX), 'Expected IRN in payload');
    }

    @IsTest
    static void testBuildEwayBillByIrnBody_RailMode_OmitsVehType() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId, 'Requires Invoice__c + related objects');

        // Transport_Mode__c is often a restricted picklist; literal "Rail" may not exist in every org.
        String railPicklistVal = null;
        Map<String, Schema.SObjectField> fm = Invoice__c.SObjectType.getDescribe().fields.getMap();
        if (fm.containsKey('transport_mode__c')) {
            Schema.DescribeFieldResult d = fm.get('transport_mode__c').getDescribe();
            if (d.getType() == Schema.DisplayType.Picklist) {
                for (Schema.PicklistEntry pe : d.getPicklistValues()) {
                    if (pe == null || !pe.isActive()) {
                        continue;
                    }
                    String v = pe.getValue();
                    String lab = pe.getLabel();
                    if ('2'.equals(v)
                        || (v != null && v.toUpperCase().contains('RAIL'))
                        || (lab != null && lab.toUpperCase().contains('RAIL'))) {
                        railPicklistVal = v;
                        break;
                    }
                }
            }
        }
        if (String.isBlank(railPicklistVal)) {
            return;
        }

        SObject inv = new Invoice__c(Id = invId);
        inv.put('IRN_Number__c', CygnetIntegrationHttpCalloutMock.MOCK_IRN_HEX);
        inv.put('Vehicle_Number__c', '');
        inv.put('Transporter_Name__c', 'Rail Carrier');
        inv.put('Transport_Mode__c', railPicklistVal);
        inv.put('Transport_Distance__c', 100);
        update inv;

        Test.startTest();
        String json = InvoiceToCygnetMapper.buildEwayBillByIrnBody(invId);
        Test.stopTest();

        System.assert(!json.contains('VehType'), 'Road-only VehType must not appear for Rail transport');
        System.assert(json.contains('"TransMode":"2"'), 'Expected TransMode 2 for Rail');
    }

    @IsTest
    static void testBuildEwayBillPdfCriterias_MatchesEInvoicePdfCriterias() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(false);
        System.assertNotEquals(null, invId);

        Test.startTest();
        String einv = InvoiceToCygnetMapper.buildEInvoicePdfCriterias(invId);
        String ewb = InvoiceToCygnetMapper.buildEwayBillPdfCriterias(invId);
        Test.stopTest();

        System.assertEquals(einv, ewb);
    }

    @IsTest
    static void testBuildEInvoiceSaveBody_UnderSsPath_WhenRecordTypeAvailable() {
        Id invId = CygnetIntegrationTestData.createInvoiceWithLine(true);
        System.assertNotEquals(null, invId);

        Invoice__c inv = [
            SELECT RecordType.DeveloperName
            FROM Invoice__c
            WHERE Id = :invId
            LIMIT 1
        ];
        if (
            inv.RecordType == null
            || inv.RecordType.DeveloperName == null
            || !inv.RecordType.DeveloperName.equalsIgnoreCase('Secondary_Invoice_Under_SS')
        ) {
            return;
        }

        Test.startTest();
        String json = InvoiceToCygnetMapper.buildEInvoiceSaveBody(invId);
        Test.stopTest();

        System.assert(json.contains('SellerDtls'), 'Expected SellerDtls');
        System.assert(json.contains('ItemList'), 'Expected ItemList');
    }
}