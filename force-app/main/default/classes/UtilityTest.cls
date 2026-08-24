@isTest
public class UtilityTest {
    @testSetup
    static void setupTestData() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Contact con = new Contact(FirstName = 'Test', LastName = 'Contact', AccountId = acc.Id);
        insert con;
    }
    
    @isTest
    static void testSoqlQuery() {
        List<sObject> result = Utility.soqlQuery('SELECT Id, Name FROM Account');
        System.assertNotEquals(0, result.size(), 'Query should return at least one record.');
    }
    
    @isTest
    static void testSoqlQueryWithBinds() {
        Map<String, Object> bindVars = new Map<String, Object>{'name' => 'Test Account'};
        List<sObject> result = Utility.soqlQuery('SELECT Id, Name FROM Account WHERE Name = :name', bindVars, System.AccessLevel.USER_MODE);
        System.assertNotEquals(0, result.size(), 'Query with bind variables should return at least one record.');
    }
    
    @isTest
    static void testRemoveObjectFields() {
        Account acc = [SELECT Id, Name FROM Account LIMIT 1];
        
        Map<String, Object> modifiedFields = Utility.removeObjectFields(acc, new List<String>{'Id'});
        System.assert(!modifiedFields.containsKey('Id'), 'Id field should be removed from the map.');
    }
}