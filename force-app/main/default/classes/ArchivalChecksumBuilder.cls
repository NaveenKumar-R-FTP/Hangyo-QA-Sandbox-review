public class ArchivalChecksumBuilder {

    public static String buildChecksum(List<Map<String, Object>> records) {
        if (records == null) {
            records = new List<Map<String, Object>>();
        }

        List<Map<String, Object>> recordsCopy = new List<Map<String, Object>>(records);
        recordsCopy.sort(new SortRecordsById());

        List<String> recordJsonStrings = new List<String>();
        for (Map<String, Object> record : recordsCopy) {
            List<String> fieldNames = new List<String>(record.keySet());
            fieldNames.sort();

            List<String> fieldJsonPieces = new List<String>();
            for (String fieldName : fieldNames) {
                Object value = record.get(fieldName);
                fieldJsonPieces.add(JSON.serialize(fieldName) + ':' + valueToJson(value));
            }
            recordJsonStrings.add('{' + String.join(fieldJsonPieces, ',') + '}');
        }

        String canonicalJson = '[' + String.join(recordJsonStrings, ',') + ']';
        System.debug('CHECKSUM_INPUT : ' + canonicalJson);
        Blob hashInput = Blob.valueOf(canonicalJson);
        Blob hash = Crypto.generateDigest('SHA-256', hashInput);
        String hexHash = EncodingUtil.convertToHex(hash);
        return 'sha256:' + hexHash;
    }

    private static String valueToJson(Object value) {
        if (value == null) {
            return 'null';
        } else if (value instanceof Decimal) {
            return formatNumberForChecksum((Decimal) value);
        } else if (value instanceof Double) {
            Decimal cleaned = Decimal.valueOf((Double) value).stripTrailingZeros();
            return String.valueOf(cleaned);
        } else if (value instanceof Integer || value instanceof Long) {
            return String.valueOf(value);
        } else if (value instanceof Boolean) {
            return String.valueOf(value);
        } else if (value instanceof Date) {
            return JSON.serialize(String.valueOf((Date) value));
        } else if (value instanceof Datetime) {
            return JSON.serialize(((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''));
        } else {
            return JSON.serialize(String.valueOf(value));
        }
    }
    
    private static String formatNumberForChecksum(Decimal value) {
        if (value == null) {
            return null;
        }
        String s = String.valueOf(value);
        if (s.contains('.')) {
            while (s.endsWith('0')) {
                s = s.substring(0, s.length() - 1);
            }
            if (s.endsWith('.')) {
                s = s.substring(0, s.length() - 1);
            }
        }
        return s;
    }

    private class SortRecordsById implements Comparator<Map<String, Object>> {
        public Integer compare(Map<String, Object> a, Map<String, Object> b) {
            String idA = a.get('Id') == null ? '' : String.valueOf(a.get('Id'));
            String idB = b.get('Id') == null ? '' : String.valueOf(b.get('Id'));
            return idA.compareTo(idB);
        }
    }
}