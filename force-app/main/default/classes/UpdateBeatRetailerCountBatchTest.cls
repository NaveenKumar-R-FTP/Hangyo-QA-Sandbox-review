/*
Test Class Name : UpdateBeatRetailerCountBatchTest
Written By : Fuzail
Created Date : 22/12/2025
Last Modified Date: 22/12/2025
*/
@isTest
public class UpdateBeatRetailerCountBatchTest {

    @testSetup
    static void setupData() {

        // Required custom setting (because Account before-insert runs)
        RetailerCodeSetting__c setting =
            new RetailerCodeSetting__c(Name = 'SF', Latest_Code__c = 100);
        insert setting;

        // Get Retailer Record Type
        Id retailerRtId = Schema.SObjectType.Account
            .getRecordTypeInfosByDeveloperName()
            .get('Retailer')
            .getRecordTypeId();

        // Create Beats
        Beat__c beat1 = new Beat__c(Name = 'Beat A');
        Beat__c beat2 = new Beat__c(Name = 'Beat B');
        insert new List<Beat__c>{ beat1, beat2 };

        // Create Retailer Accounts under Beats
        List<Account> retailers = new List<Account>{
            new Account(
                Name = 'Retailer 1',
                RecordTypeId = retailerRtId,
                Is_Active__c = true,
                Beats_Name__c = beat1.Id
            ),
            new Account(
                Name = 'Retailer 2',
                RecordTypeId = retailerRtId,
                Is_Active__c = true,
                Beats_Name__c = beat1.Id
            ),
            new Account(
                Name = 'Retailer 3',
                RecordTypeId = retailerRtId,
                Is_Active__c = true,
                Beats_Name__c = beat2.Id
            )
        };
        insert retailers;
    }

    @isTest
    static void testBatchUpdatesRetailerCount() {

        // Before batch
        List<Beat__c> beforeBeats = [
            SELECT Id, Name, Number_Of_Retailers__c
            FROM Beat__c
            WHERE Name IN ('Beat A', 'Beat B')
        ];

        Test.startTest();
        Database.executeBatch(new UpdateBeatRetailerCountBatch(), 200);
        Test.stopTest();

        // After batch
        List<Beat__c> afterBeats = [
            SELECT Name, Number_Of_Retailers__c
            FROM Beat__c
            WHERE Name IN ('Beat A', 'Beat B')
        ];

        Map<String, Integer> expectedCounts = new Map<String, Integer>{
            'Beat A' => 2,
            'Beat B' => 1
        };

        for (Beat__c b : afterBeats) {
            System.assertEquals(
                expectedCounts.get(b.Name),
                b.Number_Of_Retailers__c,
                'Incorrect retailer count for ' + b.Name
            );
        }
    }
    @isTest
    static void testBeatWithZeroRetailers() {

    Beat__c emptyBeat = new Beat__c(Name = 'Empty Beat');
    insert emptyBeat;

    Test.startTest();
    Database.executeBatch(new UpdateBeatRetailerCountBatch(), 200);
    Test.stopTest();

    Beat__c updatedBeat = [
        SELECT Number_Of_Retailers__c
        FROM Beat__c
        WHERE Id = :emptyBeat.Id
    ];

    System.assertEquals(
        null,
        updatedBeat.Number_Of_Retailers__c,
        'Beat with no retailers should have count 0'
    );
   }

}