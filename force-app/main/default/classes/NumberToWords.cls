public class NumberToWords {
    private static final List<String> belowTwenty = 
        new List<String>{'', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven',
                         'Eight', 'Nine', 'Ten', 'Eleven', 'Twelve', 'Thirteen',
                         'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'};

    private static final List<String> tens = 
        new List<String>{'', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty',
                         'Seventy', 'Eighty', 'Ninety'};

    public static String convert(Long num) {
        if (num == 0) return 'Zero';
        return convertHelper(num).trim();
    }

    private static String convertHelper(Long num) {
        if (num < 20) return belowTwenty[(Integer)num];
        else if (num < 100) return tens[(Integer)(num/10)] + ' ' + belowTwenty[(Integer)Math.mod(num,10)];
        else if (num < 1000) return belowTwenty[(Integer)(num/100)] + ' Hundred ' + convertHelper(Math.mod(num,100));
        else if (num < 100000) return convertHelper(num/1000) + ' Thousand ' + convertHelper(Math.mod(num,1000));
        else if (num < 10000000) return convertHelper(num/100000) + ' Lakh ' + convertHelper(Math.mod(num,100000));
        else return convertHelper(num/10000000) + ' Crore ' + convertHelper(Math.mod(num,10000000));
    }
}