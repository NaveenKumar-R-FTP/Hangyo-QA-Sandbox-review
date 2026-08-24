public class NumberToWordsUtility {
@AuraEnabled
    public static String numberToWordsInINR(Decimal num) {
        // Handle null or zero cases early
        if (num == null || num == 0) {
            return 'Zero Rupees';
        }

        // Arrays for unit and tens
        String[] units = new String[]{
            '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 
            'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 
            'Seventeen', 'Eighteen', 'Nineteen'
        };
        
        String[] tens = new String[]{
            '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
        };
        
        String result = '';
        
        // Handle fractional part
        Decimal intPart = Math.floor(num);
        
        Decimal fracPart = num - intPart;
        Integer firstDigit ;
        
        if (intPart >= 999999999) {
            firstDigit = (Integer) (intPart / 1000000000); // Extract the first 9 digits
            result += units[firstDigit] + ' Hundred and ';
            String numberStr = String.valueOf(intPart);
       		String modifiedStr = numberStr.substring(1); // Remove the first character
            intPart=Integer.valueOf(modifiedStr);
             system.debug('firstDigit- '+firstDigit+'  - modifiedStr-  ' +modifiedStr + '  - result - '+result);
        }
        

        Integer crore = (Integer) (intPart / 10000000);//9876543210.75
        system.debug('intPart- '+intPart+'  - fracPart-  ' +fracPart + '  - crore - '+crore);
        //intPart- 876543210  - fracPart-  0.75  - crore - 87
        Integer lakh = (Integer) ((intPart - (crore * 10000000)) / 100000);
        Integer thousand = (Integer) ((intPart - (crore * 10000000) - (lakh * 100000)) / 1000);
        Integer hundred = (Integer) ((intPart - (crore * 10000000) - (lakh * 100000) - (thousand * 1000)) / 100);
        Integer tensUnit = (Integer) (intPart - (crore * 10000000) - (lakh * 100000) - (thousand * 1000) - (hundred * 100));

        // Convert crore part
        if (crore > 0) {
            result += convertNumberToWords(crore, units, tens) + ' Crore ';
        }

        // Convert lakh part
        if (lakh > 0) {
            result += convertNumberToWords(lakh, units, tens) + ' Lakh ';
        }

        // Convert thousand part
        if (thousand > 0) {
            result += convertNumberToWords(thousand, units, tens) + ' Thousand ';
        }

        // Convert hundred part
        if (hundred > 0) {
            result += units[hundred] + ' Hundred ';
        }

        // Convert tens and ones part
        if (tensUnit > 0) {
            if(result != ''){
            result +='and '+convertNumberToWords(tensUnit, units, tens);
            }
            else{
                 result +=' '+convertNumberToWords(tensUnit, units, tens);
            }
        }

        // Add "Rupees" at the end
        result = result.trim() + ' Rupees';
        
        // Handle paisa (fractional part)
        if (fracPart > 0) {
            Integer paisa = (Integer) (fracPart * 100);
            result += ' and ' + convertNumberToWords(paisa, units, tens) + ' Paise';
        }

        return result+' Only';
    }

    // Helper method to convert a number into words using units and tens arrays
    private static String convertNumberToWords(Integer num, String[] units, String[] tens) {
        String result = '';
         system.debug('num- '+num+'  - units-  ' +units + '  - tens - '+tens);
        if (num < 20) {
            // Direct lookup for numbers less than 20
            result = units[num];
        } else if (num < 100) {
            // For numbers between 20 and 99
            Integer tensPlace = num / 10;
            Integer onesPlace = num - (tensPlace * 10);
            result = tens[tensPlace];
            if (onesPlace > 0) {
                result += ' ' + units[onesPlace];
            }
        } else if (num < 1000) {
            // For numbers between 100 and 999
            Integer hundredsPlace = num / 100;
            Integer remainder = num - (hundredsPlace * 100);
            result = units[hundredsPlace] + ' Hundred';
            if (remainder > 0) {
                result += 'and ' + convertNumberToWords(remainder, units, tens);
            }
        }

        return result.trim();
    }
}