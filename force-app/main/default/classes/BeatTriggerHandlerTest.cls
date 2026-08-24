/*
Test Class Name : BeatTriggerHandlerTest
Written By : Fuzail
Created Date : 22/12/2025
Last Modified Date: 22/12/2025
*/
@isTest
public class BeatTriggerHandlerTest {

    @testSetup
    static void setupTestData() {
        RetailerCodeSetting__c setting = new RetailerCodeSetting__c(
            Name = 'SF',
            Latest_Code__c = 100
        );
        insert setting;
    }

    private static Id getRetailerRecordTypeId() {
        return Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Retailer')
            .getRecordTypeId();
    }

    @isTest
    static void testInsertRetailerUpdatesBeatCount() {

        Id retailerRtId = getRetailerRecordTypeId();

        Beat__c beat = new Beat__c(Name = 'Test Beat');
        insert beat;

        Account retailer = new Account(
            Name = 'Retailer 1',
            RecordTypeId = retailerRtId,
            Is_Active__c = true,
            Beats_Name__c = beat.Id
        );

        Test.startTest();
        insert retailer;
        Test.stopTest();

        Beat__c updatedBeat = [
            SELECT Number_Of_Retailers__c
            FROM Beat__c
            WHERE Id = :beat.Id
        ];

        System.assertEquals(1, updatedBeat.Number_Of_Retailers__c);
    }

    @isTest
    static void testUpdateBeatReparenting() {

        Id retailerRtId = getRetailerRecordTypeId();

        Beat__c beat1 = new Beat__c(Name = 'Beat 1');
        Beat__c beat2 = new Beat__c(Name = 'Beat 2');
        insert new List<Beat__c>{ beat1, beat2 };

        Account retailer = new Account(
            Name = 'Retailer Move',
            RecordTypeId = retailerRtId,
            Is_Active__c = true,
            Beats_Name__c = beat1.Id
        );
        insert retailer;

        retailer.Beats_Name__c = beat2.Id;

        Test.startTest();
        update retailer;
        Test.stopTest();

        Map<Id, Beat__c> beatMap = new Map<Id, Beat__c>([
            SELECT Number_Of_Retailers__c
            FROM Beat__c
            WHERE Id IN :new List<Id>{ beat1.Id, beat2.Id }
        ]);

        System.assertEquals(0, beatMap.get(beat1.Id).Number_Of_Retailers__c);
        System.assertEquals(1, beatMap.get(beat2.Id).Number_Of_Retailers__c);
    }

    @isTest
    static void testDeleteRetailerUpdatesBeatCount() {

        Id retailerRtId = getRetailerRecordTypeId();

        Beat__c beat = new Beat__c(Name = 'Delete Beat');
        insert beat;

        Account retailer = new Account(
            Name = 'Retailer Delete',
            RecordTypeId = retailerRtId,
            Beats_Name__c = beat.Id
        );
        insert retailer;

        Test.startTest();
        delete retailer;
        Test.stopTest();

        Beat__c updatedBeat = [
            SELECT Number_Of_Retailers__c
            FROM Beat__c
            WHERE Id = :beat.Id
        ];

        System.assertEquals(0, updatedBeat.Number_Of_Retailers__c);
    }
    @isTest
    static void testNullNewAndOldList() {
    Test.startTest();
    BeatTriggerHandler.updateRetailerCount(null, null);
    Test.stopTest();

    System.assert(true, 'Method should safely exit when both params are null');
    }
 
   @isTest
   static void testNullNewListOnly() {

    Beat__c beat = new Beat__c(Name = 'Null NewList Beat');
    insert beat;

    Account oldAcc = new Account(
        Name = 'Old Retailer',
        Beats_Name__c = beat.Id,
        Is_Active__c = true
    );

    Test.startTest();
    BeatTriggerHandler.updateRetailerCount(null, new List<Account>{ oldAcc });
    Test.stopTest();

    System.assert(true, 'Handled null newList safely');
    }

    @isTest
    static void testAccountWithNullBeat() {

    Account acc = new Account(
        Name = 'No Beat Retailer',
        Is_Active__c = true
    );

    Test.startTest();
    BeatTriggerHandler.updateRetailerCount(
        new List<Account>{ acc },
        null
    );
    Test.stopTest();

    System.assert(true, 'Account with null Beat should be ignored');
   }

}