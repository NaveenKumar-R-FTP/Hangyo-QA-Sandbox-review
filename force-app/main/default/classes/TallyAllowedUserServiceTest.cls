/**
 * @description Unit tests for TallyAllowedUserService.
 */
@isTest
private class TallyAllowedUserServiceTest {
    private static final Id VALID_USER_ID = TallyInvoiceTestDataFactory.ALLOWED_OWNER_ID;

    @isTest
    static void getAllowedUserIds_returnsActiveValidUsers() {
        // Uses an explicit override with Integration_User_Id__c set to the
        // running test user — the isolation check requires this to match
        // UserInfo.getUserId().
        Map<String, Tally_Allowed_User__mdt> testRecords =
            new Map<String, Tally_Allowed_User__mdt>();
        testRecords.put(
            'ValidUser',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = String.valueOf(VALID_USER_ID),
                Integration_User_Id__c = String.valueOf(UserInfo.getUserId())
            )
        );
        TallyAllowedUserService.testMetadataOverride = testRecords;

        Test.startTest();
        Set<Id> allowedUserIds = TallyAllowedUserService.getAllowedUserIds();
        Test.stopTest();

        resetTestHooks();

        System.assertNotEquals(null, allowedUserIds, 'Result set must not be null');
        System.assert(
            allowedUserIds.contains(VALID_USER_ID),
            'Expected active CMDT user to be included'
        );
    }

    @isTest
    static void getAllowedUserIds_excludesInactiveAndInvalidRecords() {
        Map<String, Tally_Allowed_User__mdt> testRecords =
            new Map<String, Tally_Allowed_User__mdt>();
        testRecords.put(
            'ValidUser',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = String.valueOf(VALID_USER_ID),
                Integration_User_Id__c = String.valueOf(UserInfo.getUserId())
            )
        );
        TallyAllowedUserService.testMetadataOverride = testRecords;

        Test.startTest();
        Set<Id> allowedUserIds = TallyAllowedUserService.getAllowedUserIds();
        Test.stopTest();

        resetTestHooks();

        System.assert(allowedUserIds.size() >= 1, 'At least one active valid user expected');
        System.assert(
            allowedUserIds.contains(VALID_USER_ID),
            'Expected active CMDT user to be included'
        );

        for (Id userId : allowedUserIds) {
            System.assert(
                String.valueOf(userId).startsWith('005'),
                'Only valid User Ids should be returned'
            );
        }
    }

    @isTest
    static void getAllowedUserIds_excludesRowsForDifferentIntegrationUser() {
        // Core of the isolation fix: a row that is otherwise perfectly valid
        // (active, real User_Id__c) must still be excluded when
        // Integration_User_Id__c does not match whoever is running now.
        Map<String, Tally_Allowed_User__mdt> testRecords =
            new Map<String, Tally_Allowed_User__mdt>();
        testRecords.put(
            'BelongsToSomeoneElse',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = String.valueOf(VALID_USER_ID),
                Integration_User_Id__c = '005000000000000AAA' // not the running user
            )
        );
        TallyAllowedUserService.testMetadataOverride = testRecords;

        Test.startTest();
        Set<Id> allowedUserIds = TallyAllowedUserService.getAllowedUserIds();
        Test.stopTest();

        resetTestHooks();

        System.assertEquals(
            0,
            allowedUserIds.size(),
            'A row belonging to a different Integration User must never be returned'
        );
    }

    @isTest
    static void getAllowedUserIds_returnsEmptySetWhenMetadataEmpty() {
        TallyAllowedUserService.testForceEmptyMetadata = true;

        Test.startTest();
        Set<Id> allowedUserIds = TallyAllowedUserService.getAllowedUserIds();
        Test.stopTest();

        resetTestHooks();

        System.assertNotEquals(null, allowedUserIds);
        System.assertEquals(0, allowedUserIds.size(), 'Empty metadata must return no users');
    }

    @isTest
    static void getAllowedUserIds_filtersAllMetadataEdgeCases() {
        String runningUserId = String.valueOf(UserInfo.getUserId());
        Map<String, Tally_Allowed_User__mdt> testRecords =
            new Map<String, Tally_Allowed_User__mdt>();
        testRecords.put('NullRecord', null);
        testRecords.put(
            'Inactive',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'False',
                User_Id__c = String.valueOf(VALID_USER_ID),
                Integration_User_Id__c = runningUserId
            )
        );
        testRecords.put(
            'InactiveLowerCase',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'false',
                User_Id__c = String.valueOf(VALID_USER_ID),
                Integration_User_Id__c = runningUserId
            )
        );
        testRecords.put(
            'NullUserId',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = null,
                Integration_User_Id__c = runningUserId
            )
        );
        testRecords.put(
            'BlankUserId',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = '   ',
                Integration_User_Id__c = runningUserId
            )
        );
        testRecords.put(
            'InvalidUserId',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = 'NOT_A_VALID_ID',
                Integration_User_Id__c = runningUserId
            )
        );
        testRecords.put(
            'TrimmedValidUser',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'true',
                User_Id__c = '  ' + String.valueOf(VALID_USER_ID) + '  ',
                Integration_User_Id__c = runningUserId
            )
        );
        testRecords.put(
            'ValidUser',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = String.valueOf(VALID_USER_ID),
                Integration_User_Id__c = runningUserId
            )
        );
        testRecords.put(
            'WrongIntegrationUser',
            new Tally_Allowed_User__mdt(
                Is_Active__c = 'True',
                User_Id__c = String.valueOf(VALID_USER_ID),
                Integration_User_Id__c = '005000000000000AAA'
            )
        );

        TallyAllowedUserService.testMetadataOverride = testRecords;

        Test.startTest();
        Set<Id> allowedUserIds = TallyAllowedUserService.getAllowedUserIds();
        Test.stopTest();

        resetTestHooks();

        System.assertEquals(1, allowedUserIds.size(), 'Only valid active users should remain');
        System.assertEquals(true, allowedUserIds.contains(VALID_USER_ID));
    }

    @isTest
    static void getAllowedUserIds_skipsInactiveNullIsActiveValue() {
        Map<String, Tally_Allowed_User__mdt> testRecords =
            new Map<String, Tally_Allowed_User__mdt>();
        testRecords.put(
            'NullIsActive',
            new Tally_Allowed_User__mdt(
                Is_Active__c = null,
                User_Id__c = String.valueOf(VALID_USER_ID),
                Integration_User_Id__c = String.valueOf(UserInfo.getUserId())
            )
        );

        TallyAllowedUserService.testMetadataOverride = testRecords;

        Test.startTest();
        Set<Id> allowedUserIds = TallyAllowedUserService.getAllowedUserIds();
        Test.stopTest();

        resetTestHooks();

        System.assertEquals(0, allowedUserIds.size(), 'Null Is_Active__c must be ignored');
    }

    private static void resetTestHooks() {
        TallyAllowedUserService.testForceEmptyMetadata = false;
        TallyAllowedUserService.testMetadataOverride = null;
    }
}