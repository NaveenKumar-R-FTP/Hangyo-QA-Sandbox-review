@IsTest
public class GetPicklistHelperTest {
    
    @IsTest
    static void testValidPicklistFetch() {
        // Act: Call helper for a standard object field with picklist
        List<GetPicklistHelper.PicklistOption> result = 
            GetPicklistHelper.getPicklistValues('Case', 'Status');
        
        // Assert
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.size() > 0, 'Picklist values should be returned for Case.Status');
        System.assertNotEquals(null, result[0].label, 'Label should not be null');
        System.assertNotEquals(null, result[0].value, 'Value should not be null');
    }
    
    @IsTest
    static void testInvalidObject() {
        // Act
        List<GetPicklistHelper.PicklistOption> result = 
            GetPicklistHelper.getPicklistValues('InvalidObject__c', 'SomeField__c');
        
        // Assert
        System.assertEquals(0, result.size(), 'Invalid object should return empty list');
    }
    
}