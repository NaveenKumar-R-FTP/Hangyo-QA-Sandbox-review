global class PayloadSigner {
    
    /*public static String generatePayloadChecksum(Object payload) {
        // Step 1: Normalize ANY object/wrapper/SObject into standard Maps/Lists
        String standardJson = JSON.serialize(payload);
        Map<String, Object> normalizedMap = (Map<String, Object>) JSON.deserializeUntyped(standardJson);
        
        // Step 2: Convert to an alphabetically sorted canonical JSON string
        String canonicalJson = serializeAlphabetical(normalizedMap);
        
        // Step 3: Standard Crypto Digest and Hex conversion
        Blob payloadBlob = Blob.valueOf(canonicalJson);
        Blob digestBlob = Crypto.generateDigest('SHA-256', payloadBlob);
        return EncodingUtil.convertToHex(digestBlob);
    }*/

    public static String serializeAlphabetical(Map<String, Object> sourceMap) {
        JSONGenerator gen = JSON.createGenerator(false);
        writeMapRecursive(gen, sourceMap);
        return gen.getAsString();
    }
    
    private static void writeMapRecursive(JSONGenerator gen, Map<String, Object> sourceMap) {
        gen.writeStartObject();
        
        List<String> sortedKeys = new List<String>(sourceMap.keySet());
        sortedKeys.sort();
        
        for (String key : sortedKeys) {
            Object value = sourceMap.get(key);
            
            // Check for nulls first
            if (value == null || value == '') {
                gen.writeNullField(key);
            }
            
            gen.writeFieldName(key);
            
            // Because of deserializeUntyped, values will ONLY be one of these types:
            if (value instanceof Map<String, Object>) {
                writeMapRecursive(gen, (Map<String, Object>) value);
            } else if (value instanceof List<Object>) {
                writeList(gen, (List<Object>) value);
            } else if (value instanceof String) {
                gen.writeString((String) value);
            } else if (value instanceof Boolean) {
                gen.writeBoolean((Boolean) value);
            } else if (value instanceof Decimal || value instanceof Double || value instanceof Integer || value instanceof Long) {
                gen.writeNumber((Decimal) value);
            } else {
                // Safeguard fallback that safely stringifies anything else
                gen.writeString(String.valueOf(value));
            }
        }
        gen.writeEndObject();
    }
    
    private static void writeList(JSONGenerator gen, List<Object> sourceList) {
        gen.writeStartArray();
        for (Object item : sourceList) {
            if (item instanceof Map<String, Object>) {
                writeMapRecursive(gen, (Map<String, Object>) item);
            } else if (item instanceof List<Object>) {
                writeList(gen, (List<Object>) item);
            } else if (item instanceof String) {
                gen.writeString((String) item);
            } else if (item instanceof Boolean) {
                gen.writeBoolean((Boolean) item);
            } else if (item instanceof Decimal || item instanceof Double || item instanceof Integer || item instanceof Long) {
                gen.writeNumber((Decimal) item);
            } else if (item == null) {
                gen.writeNull();
            } else {
                gen.writeString(String.valueOf(item));
            }
        }
        gen.writeEndArray();
    }
}