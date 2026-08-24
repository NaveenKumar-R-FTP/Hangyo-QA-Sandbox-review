public class Utility {
    
    public static List<sObject> soqlQuery(String queryStr) {
        List<sObject> sobjList = Database.query(queryStr);
        return sobjList;
    }
    
    public static List<sObject> soqlQuery(String queryStr, Map<String, Object> bindVariablesMap, System.AccessLevel accessLevel) {
        List<sObject> sobjList = Database.queryWithBinds(queryStr, bindVariablesMap, accessLevel);
        return sobjList;
    }
    
    

    public static Map<String, Object> removeObjectFields(Object objInstance, List<String> removeFieldList) {
        // Get map of the object fields. The populated fields map is read-only so pass it into another map to get an editable copy
        Map<String, Object> fieldMap = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(objInstance));
        for(String delField : removeFieldList) { //Remove the fields
            fieldMap.remove(delField);
        }
        return fieldMap; //Convert the map into sObject using serialize/deserialize trick in your class JSON.deserialize( JSON.serialize( fieldMap ), Object.class ); 
    }
}