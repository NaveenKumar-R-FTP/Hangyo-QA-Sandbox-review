@isTest
public class NumberToWordsUtilityTest {
    
    @isTest
    public static void testNumberToWordsInINR() {
        
        // Test Case 1: Simple integer without paisa
        Decimal amount1 = 1234567;
        String expected1 = 'Twelve Lakh Thirty Four Thousand Five Hundred and Sixty Seven Rupees Only';
        String result1 = NumberToWordsUtility.numberToWordsInINR(amount1);
        System.assertEquals(expected1, result1, 'Test Case 1 Failed');
        
        // Test Case 2: Amount with paisa (fractional part)
        Decimal amount2 = 1234567.89;
        String expected2 = 'Twelve Lakh Thirty Four Thousand Five Hundred and Sixty Seven Rupees and Eighty Nine Paise Only';
        String result2 = NumberToWordsUtility.numberToWordsInINR(amount2);
        System.assertEquals(expected2, result2, 'Test Case 2 Failed');
        
        // Test Case 3: Single digit amount
        Decimal amount3 = 9;
        String expected3 = 'Nine Rupees Only';
        String result3 = NumberToWordsUtility.numberToWordsInINR(amount3);
        System.assertEquals(expected3, result3, 'Test Case 3 Failed');
        
        // Test Case 4: Amount with multiple zeros
        Decimal amount4 = 100500;
        String expected4 = 'One Lakh Five Hundred Rupees Only';
        String result4 = NumberToWordsUtility.numberToWordsInINR(amount4);
        System.assertEquals(expected4, result4, 'Test Case 4 Failed');
        
        // Test Case 5: Amount with paisa under 10
        Decimal amount5 = 1234567.04;
        String expected5 = 'Twelve Lakh Thirty Four Thousand Five Hundred and Sixty Seven Rupees and Four Paise Only';
        String result5 = NumberToWordsUtility.numberToWordsInINR(amount5);
        System.assertEquals(expected5, result5, 'Test Case 5 Failed');
        
        // Test Case 6: Round figure with zero paisa
        Decimal amount6 = 5000;
        String expected6 = 'Five Thousand Rupees Only';
        String result6 = NumberToWordsUtility.numberToWordsInINR(amount6);
        System.assertEquals(expected6, result6, 'Test Case 6 Failed');
        
        // Test Case 7: Zero amount
        Decimal amount7 = 0;
        String expected7 = 'Zero Rupees';
        String result7 = NumberToWordsUtility.numberToWordsInINR(amount7);
        System.assertEquals(expected7, result7, 'Test Case 7 Failed');
        
        // Test Case 8: Very large number
        Decimal amount8 = 876543210.75;
        String expected8 = 'Eighty Seven Crore Sixty Five Lakh Forty Three Thousand Two Hundred and Ten Rupees and Seventy Five Paise Only';
           
        String result8 = NumberToWordsUtility.numberToWordsInINR(amount8);
        System.assertEquals(expected8, result8, 'Test Case 8 Failed');
        
        // Test Case 9: Paisa less than 10
        Decimal amount9 = 1234567.03;
        String expected9 = 'Twelve Lakh Thirty Four Thousand Five Hundred and Sixty Seven Rupees and Three Paise Only';
        String result9 = NumberToWordsUtility.numberToWordsInINR(amount9);
        System.assertEquals(expected9, result9, 'Test Case 9 Failed');
        
           
        // Test Case 10: Very large number
        Decimal amount10 = 1876543210.75;
        String expected10 = 'One Hundred and Eighty Seven Crore Sixty Five Lakh Forty Three Thousand Two Hundred and Ten Rupees and Seventy Five Paise Only';
           
        String result10 = NumberToWordsUtility.numberToWordsInINR(amount10);
        System.assertEquals(expected10, result10, 'Test Case 10 Failed');
        
                // Test Case 11:100 to 999
        Decimal amount11 = 898;
        String expected11 = 'Eight Hundred and Ninety Eight Rupees Only';
                                 
        String result11 = NumberToWordsUtility.numberToWordsInINR(amount11);
        System.assertEquals(expected11, result11, 'Test Case 10 Failed');
    }
}