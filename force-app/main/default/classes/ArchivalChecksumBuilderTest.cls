@isTest
private class ArchivalChecksumBuilderTest {

    @isTest
    static void testBuildChecksum_nullInput_returnsChecksumForEmptyArray() {
        Test.startTest();
        String checksum = ArchivalChecksumBuilder.buildChecksum(null);
        Test.stopTest();

        System.assertNotEquals(null, checksum, 'Checksum should not be null for null input');
        System.assert(checksum.startsWith('sha256:'), 'Checksum should be prefixed with sha256:');

        // Empty list canonical JSON is '[]', verify determinism against manual hash
        Blob hashInput = Blob.valueOf('[]');
        Blob hash = Crypto.generateDigest('SHA-256', hashInput);
        String expected = 'sha256:' + EncodingUtil.convertToHex(hash);
        System.assertEquals(expected, checksum, 'Checksum for null input should match hash of empty array');
    }

    @isTest
    static void testBuildChecksum_emptyList_returnsSameAsNull() {
        Test.startTest();
        String checksumFromNull = ArchivalChecksumBuilder.buildChecksum(null);
        String checksumFromEmpty = ArchivalChecksumBuilder.buildChecksum(new List<Map<String, Object>>());
        Test.stopTest();

        System.assertEquals(checksumFromNull, checksumFromEmpty,
            'Null and empty list inputs should produce identical checksums');
    }

    @isTest
    static void testBuildChecksum_singleRecord_isDeterministic() {
        Map<String, Object> record1 = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Name' => 'Test Item',
            'Quantity__c' => 10
        };

        List<Map<String, Object>> records = new List<Map<String, Object>>{ record1 };

        Test.startTest();
        String checksum1 = ArchivalChecksumBuilder.buildChecksum(records);
        String checksum2 = ArchivalChecksumBuilder.buildChecksum(records);
        Test.stopTest();

        System.assertEquals(checksum1, checksum2,
            'Checksum should be deterministic for identical input across calls');
        System.assert(checksum1.startsWith('sha256:'), 'Checksum should be prefixed correctly');
    }

    @isTest
    static void testBuildChecksum_fieldOrderIndependent() {
        // Same logical record, fields inserted in different order.
        Map<String, Object> recordA = new Map<String, Object>();
        recordA.put('Id', '001000000000001AAA');
        recordA.put('Name', 'Widget');
        recordA.put('Amount__c', 100);

        Map<String, Object> recordB = new Map<String, Object>();
        recordB.put('Amount__c', 100);
        recordB.put('Id', '001000000000001AAA');
        recordB.put('Name', 'Widget');

        List<Map<String, Object>> listA = new List<Map<String, Object>>{ recordA };
        List<Map<String, Object>> listB = new List<Map<String, Object>>{ recordB };

        Test.startTest();
        String checksumA = ArchivalChecksumBuilder.buildChecksum(listA);
        String checksumB = ArchivalChecksumBuilder.buildChecksum(listB);
        Test.stopTest();

        System.assertEquals(checksumA, checksumB,
            'Checksum must be independent of the insertion order of map keys (fields are alphabetized)');
    }

    @isTest
    static void testBuildChecksum_recordOrderIndependent_sortedById() {
        Map<String, Object> record1 = new Map<String, Object>{
            'Id' => '001000000000002AAA',
            'Name' => 'Second'
        };
        Map<String, Object> record2 = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Name' => 'First'
        };

        List<Map<String, Object>> orderXY = new List<Map<String, Object>>{ record1, record2 };
        List<Map<String, Object>> orderYX = new List<Map<String, Object>>{ record2, record1 };

        Test.startTest();
        String checksumXY = ArchivalChecksumBuilder.buildChecksum(orderXY);
        String checksumYX = ArchivalChecksumBuilder.buildChecksum(orderYX);
        Test.stopTest();

        System.assertEquals(checksumXY, checksumYX,
            'Checksum must be independent of input list order since records are sorted by Id internally');
    }

    @isTest
    static void testBuildChecksum_decimalTrailingZerosStripped() {
        // 150.00 and 150.0 and 150 should all normalize to "150" and thus
        // produce identical checksums.
        Map<String, Object> recordWithZeros = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Amount__c' => Decimal.valueOf('150.00')
        };
        Map<String, Object> recordNoZeros = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Amount__c' => Decimal.valueOf('150')
        };

        Test.startTest();
        String checksum1 = ArchivalChecksumBuilder.buildChecksum(
            new List<Map<String, Object>>{ recordWithZeros });
        String checksum2 = ArchivalChecksumBuilder.buildChecksum(
            new List<Map<String, Object>>{ recordNoZeros });
        Test.stopTest();

        System.assertEquals(checksum1, checksum2,
            'Decimal values with different trailing-zero representations should hash identically');
    }

    @isTest
    static void testBuildChecksum_decimalWithFraction_preservesSignificantDigits() {
        Map<String, Object> record = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Amount__c' => Decimal.valueOf('157.50')
        };
        Map<String, Object> recordDifferent = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Amount__c' => Decimal.valueOf('157.5')
        };

        Test.startTest();
        String checksum1 = ArchivalChecksumBuilder.buildChecksum(
            new List<Map<String, Object>>{ record });
        String checksum2 = ArchivalChecksumBuilder.buildChecksum(
            new List<Map<String, Object>>{ recordDifferent });
        Test.stopTest();

        System.assertEquals(checksum1, checksum2,
            '157.50 and 157.5 should normalize to the same significant digits and match');
    }

    @isTest
    static void testBuildChecksum_zeroDecimal_normalizesToZero() {
        Map<String, Object> record = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Amount__c' => Decimal.valueOf('0.00')
        };

        Test.startTest();
        String checksum = ArchivalChecksumBuilder.buildChecksum(new List<Map<String, Object>>{ record });
        Test.stopTest();

        System.assertNotEquals(null, checksum, 'Checksum should be generated for zero decimal values');
    }

    @isTest
    static void testBuildChecksum_differentValues_produceDifferentChecksums() {
        Map<String, Object> record1 = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Name' => 'Widget A'
        };
        Map<String, Object> record2 = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Name' => 'Widget B'
        };

        Test.startTest();
        String checksum1 = ArchivalChecksumBuilder.buildChecksum(new List<Map<String, Object>>{ record1 });
        String checksum2 = ArchivalChecksumBuilder.buildChecksum(new List<Map<String, Object>>{ record2 });
        Test.stopTest();

        System.assertNotEquals(checksum1, checksum2,
            'Different field values should produce different checksums');
    }

    @isTest
    static void testBuildChecksum_nullFieldValue_handledAsNull() {
        Map<String, Object> record = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Description__c' => null
        };

        Test.startTest();
        String checksum = ArchivalChecksumBuilder.buildChecksum(new List<Map<String, Object>>{ record });
        Test.stopTest();

        System.assertNotEquals(null, checksum, 'Checksum should handle null field values without error');
    }

    @isTest
    static void testBuildChecksum_booleanAndDateTypes() {
        Map<String, Object> record = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'IsActive__c' => true,
            'Due_Date__c' => Date.newInstance(2026, 1, 15)
        };

        Test.startTest();
        String checksum = ArchivalChecksumBuilder.buildChecksum(new List<Map<String, Object>>{ record });
        Test.stopTest();

        System.assertNotEquals(null, checksum, 'Checksum should support boolean and date field types');
    }

    @isTest
    static void testBuildChecksum_datetimeType_formattedConsistently() {
        Datetime dt = Datetime.newInstanceGmt(2026, 1, 15, 10, 30, 0);
        Map<String, Object> record = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Processed_At__c' => dt
        };

        Test.startTest();
        String checksum1 = ArchivalChecksumBuilder.buildChecksum(new List<Map<String, Object>>{ record });
        String checksum2 = ArchivalChecksumBuilder.buildChecksum(new List<Map<String, Object>>{ record });
        Test.stopTest();

        System.assertEquals(checksum1, checksum2, 'Datetime formatting should be deterministic');
    }

    @isTest
    static void testBuildChecksum_missingIdField_treatedAsEmptyStringForSort() {
        // Records without an Id key should not throw during sort - they sort
        // to the front using empty string comparison.
        Map<String, Object> recordNoId = new Map<String, Object>{
            'Name' => 'No Id Record'
        };
        Map<String, Object> recordWithId = new Map<String, Object>{
            'Id' => '001000000000001AAA',
            'Name' => 'Has Id'
        };

        List<Map<String, Object>> records = new List<Map<String, Object>>{ recordWithId, recordNoId };

        Test.startTest();
        String checksum = ArchivalChecksumBuilder.buildChecksum(records);
        Test.stopTest();

        System.assertNotEquals(null, checksum,
            'Should not throw when a record is missing an Id field');
    }

    @isTest
    static void testBuildChecksum_multipleRecords_fullScenario() {
        List<Map<String, Object>> records = new List<Map<String, Object>>();
        for (Integer i = 1; i <= 5; i++) {
            records.add(new Map<String, Object>{
                'Id' => '00100000000000' + i + 'AAA',
                'Name' => 'Item ' + i,
                'Quantity__c' => Decimal.valueOf(i * 10),
                'Active__c' => Math.mod(i, 2) == 0
            });
        }

        Test.startTest();
        String checksum = ArchivalChecksumBuilder.buildChecksum(records);
        Test.stopTest();

        System.assert(checksum.startsWith('sha256:'), 'Checksum should be correctly prefixed');
        System.assertEquals(71, checksum.length(),
            'sha256: prefix (7 chars) + 64 hex chars should equal 71 total characters');
    }
}