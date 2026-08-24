@isTest
public class CartProductWrapperTest {

    @isTest
    static void testProductWrapper() {
        // Create an instance of ProductWrapper
        CartProductWrapper.ProductWrapper product = new CartProductWrapper.ProductWrapper();

        // Set test values for the ProductWrapper fields
        product.productId = 'P123';
        product.customURL = new List<String>{'http://example.com/product1'};
        product.productImage = 'product1.jpg';
        product.productBrand = 'BrandX';
        product.quantity = 2;
        product.price = 199;
        product.productFullName = 'Product Full Name';
        product.cutomImagesData = true;
        product.productListPrice = 299.99;
        product.productOfferPrice = 199.99;
        product.sellebleSKU = 'SKU12345';
        product.isHidePrice = false;
        product.isBlankListPrice = false;
        product.isBlankOfferPrice = false;
        product.lastImage = true;
        product.selectedScheme = 'Discount Scheme';
        product.selectedSchemeId = 'Scheme123';
        product.promoType = 'VALUE';
        product.promoProductId = 'a0aBg00000A9cTtIAJ';
        product.unittotalPrice = 100;
        product.productName = 'ABC';

        // Perform assertions to verify the values
        System.assertEquals(product.productId, 'P123', 'Product ID should be P123');
        System.assertEquals(product.customURL, new List<String>{'http://example.com/product1'}, 'Custom URL list should contain the provided URL');
        System.assertEquals(product.productImage, 'product1.jpg', 'Product image should be product1.jpg');
        System.assertEquals(product.productBrand, 'BrandX', 'Product brand should be BrandX');
        System.assertEquals(product.quantity, 2, 'Product quantity should be 2');
        System.assertEquals(product.price, 199, 'Product price should be 199');
        System.assertEquals(product.productFullName, 'Product Full Name', 'Product full name should be "Product Full Name"');
        System.assertEquals(product.cutomImagesData, true, 'Custom images data should be true');
        System.assertEquals(product.productListPrice, 299.99, 'Product list price should be 299.99');
        System.assertEquals(product.productOfferPrice, 199.99, 'Product offer price should be 199.99');
        System.assertEquals(product.sellebleSKU, 'SKU12345', 'Sellable SKU should be SKU12345');
        System.assertEquals(product.isHidePrice, false, 'IsHidePrice should be false');
        System.assertEquals(product.isBlankListPrice, false, 'IsBlankListPrice should be false');
        System.assertEquals(product.isBlankOfferPrice, false, 'IsBlankOfferPrice should be false');
        System.assertEquals(product.lastImage, true, 'Last image should be true');
        System.assertEquals(product.selectedScheme, 'Discount Scheme', 'Selected scheme should be "Discount Scheme"');
        System.assertEquals(product.selectedSchemeId, 'Scheme123', 'Selected scheme ID should be Scheme123');
    }
}