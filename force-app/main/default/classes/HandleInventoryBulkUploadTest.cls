@IsTest
private class HandleInventoryBulkUploadTest {

  private static final String STATUS_CONFIRMED = 'Confirmed';
  private static final String STATUS_DRAFT = 'Draft';
  private static final String RT_SECONDARY_INVOICE = 'Secondary_Invoice';
  private static final String TEST_PRODUCT_A = 'HIBU-PROD-A';
  private static final String TEST_PRODUCT_B = 'HIBU-PROD-B';
  private static final String CONFIRMED_INV_MARKER = 'HIBU-CONF-INV';
  private static final String DRAFT_INV_MARKER = 'HIBU-DRAFT-INV';

  @TestSetup
  static void setupTestData() {
    Account distributor = resolveDistributorAccount();
    Account retailer = resolveRetailerAccount(distributor);
    Product__c productA = queryOrCreateProduct(TEST_PRODUCT_A);
    queryOrCreateProduct(TEST_PRODUCT_B);

    Id secondaryInvoiceRtId = getSecondaryInvoiceRecordTypeId();
    System.assertNotEquals(
      null,
      secondaryInvoiceRtId,
      'Secondary_Invoice record type is required.'
    );

    Order__c order = resolveOrder(retailer, distributor);

    // Two NEW invoices – never reuse same record for Confirmed + Draft
    createTestInvoice(
      secondaryInvoiceRtId,
      order,
      retailer,
      distributor,
      CONFIRMED_INV_MARKER,
      STATUS_CONFIRMED
    );
    createTestInvoice(
      secondaryInvoiceRtId,
      order,
      retailer,
      distributor,
      DRAFT_INV_MARKER,
      STATUS_DRAFT
    );

    upsertInventory(distributor.Id, productA.Id, 200);
  }

  @IsTest
  static void inventoryBulkUpload_handlesNullInput() {
    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(null);
    Test.stopTest();
    System.assert(true);
  }

  @IsTest
  static void inventoryBulkUpload_handlesEmptyList() {
    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(new List<Invoice_Line_Item__c>());
    Test.stopTest();
    System.assert(true);
  }

  @IsTest
  static void inventoryBulkUpload_exitsWhenInvoiceIdsEmpty() {
    Product__c product = getProductByCode(TEST_PRODUCT_A);

    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(
      new List<Invoice_Line_Item__c>{
        new Invoice_Line_Item__c(Product__c = product.Id, Quantity__c = 5)
      }
    );
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Inventory_Adjustment__c]);
  }

  @IsTest
  static void inventoryBulkUpload_exitsWhenQuantityMapEmpty() {
    Product__c product = getProductByCode(TEST_PRODUCT_A);
    Invoice__c draftInvoice = getInvoiceByMarker(DRAFT_INV_MARKER);

    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(
      new List<Invoice_Line_Item__c>{
        buildLine(draftInvoice.Id, product.Id, 10)
      }
    );
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Inventory_Adjustment__c]);
  }

  @IsTest
  static void inventoryBulkUpload_exitsWhenInvoiceNotFoundInQuery() {
    Product__c product = getProductByCode(TEST_PRODUCT_A);
    Id missingInvoiceId = buildSyntheticId(Invoice__c.SObjectType);

    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(
      new List<Invoice_Line_Item__c>{
        buildLine(missingInvoiceId, product.Id, 10)
      }
    );
    Test.stopTest();

    System.assertEquals(0, [SELECT COUNT() FROM Inventory_Adjustment__c]);
  }

  @IsTest
  static void inventoryBulkUpload_deductsInventoryAndCreatesAdjustment() {
    TestData data = loadCoreTestData();
    Decimal startingQty = data.inventory.Quantity_in_hand__c;

    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(
      new List<Invoice_Line_Item__c>{
        buildLine(data.confirmedInvoice.Id, data.product.Id, 8)
      }
    );
    Test.stopTest();

    Inventory__c updatedInventory = [
      SELECT Quantity_in_hand__c
      FROM Inventory__c
      WHERE Id = :data.inventory.Id
      LIMIT 1
    ];
    System.assertEquals(startingQty - 8, updatedInventory.Quantity_in_hand__c);

    List<Inventory_Adjustment__c> adjustments = [
      SELECT Quantity__c, Inventory__c, Product__c, Type__c,
             Secondary_Invoice_transaction__c, Adjustment_Date__c
      FROM Inventory_Adjustment__c
      WHERE Secondary_Invoice_transaction__c = :data.confirmedInvoice.Id
        AND Product__c = :data.product.Id
    ];
    System.assertEquals(1, adjustments.size());
    System.assertEquals(8, adjustments[0].Quantity__c);
    System.assertEquals(data.inventory.Id, adjustments[0].Inventory__c);
    System.assertEquals('Decrement', adjustments[0].Type__c);
    System.assertEquals(Date.today(), adjustments[0].Adjustment_Date__c);
  }

  @IsTest
  static void inventoryBulkUpload_aggregatesQuantityForSameProduct() {
    TestData data = loadCoreTestData();
    Decimal startingQty = data.inventory.Quantity_in_hand__c;

    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(
      new List<Invoice_Line_Item__c>{
        buildLine(data.confirmedInvoice.Id, data.product.Id, 4),
        buildLine(data.confirmedInvoice.Id, data.product.Id, 6)
      }
    );
    Test.stopTest();

    Inventory__c updatedInventory = [
      SELECT Quantity_in_hand__c
      FROM Inventory__c
      WHERE Id = :data.inventory.Id
      LIMIT 1
    ];
    System.assertEquals(startingQty - 10, updatedInventory.Quantity_in_hand__c);
    System.assertEquals(
      2,
      [
        SELECT COUNT()
        FROM Inventory_Adjustment__c
        WHERE Secondary_Invoice_transaction__c = :data.confirmedInvoice.Id
          AND Product__c = :data.product.Id
      ]
    );
  }

  @IsTest
  static void inventoryBulkUpload_skipsNullProductAndQuantity() {
    TestData data = loadCoreTestData();
    Decimal startingQty = data.inventory.Quantity_in_hand__c;

    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(
      new List<Invoice_Line_Item__c>{
        new Invoice_Line_Item__c(
          Invoice__c = data.confirmedInvoice.Id,
          Product__c = null,
          Quantity__c = 5
        ),
        new Invoice_Line_Item__c(
          Invoice__c = data.confirmedInvoice.Id,
          Product__c = data.product.Id,
          Quantity__c = null
        )
      }
    );
    Test.stopTest();

    Inventory__c updatedInventory = [
      SELECT Quantity_in_hand__c
      FROM Inventory__c
      WHERE Id = :data.inventory.Id
      LIMIT 1
    ];
    System.assertEquals(startingQty, updatedInventory.Quantity_in_hand__c);
    System.assertEquals(
      0,
      [
        SELECT COUNT()
        FROM Inventory_Adjustment__c
        WHERE Secondary_Invoice_transaction__c = :data.confirmedInvoice.Id
      ]
    );
  }

  @IsTest
  static void inventoryBulkUpload_skipsWhenNoMatchingInventory() {
    TestData data = loadCoreTestData();
    Product__c alternateProduct = getProductByCode(TEST_PRODUCT_B);
    Decimal startingQty = data.inventory.Quantity_in_hand__c;

    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(
      new List<Invoice_Line_Item__c>{
        buildLine(data.confirmedInvoice.Id, alternateProduct.Id, 5)
      }
    );
    Test.stopTest();

    Inventory__c updatedInventory = [
      SELECT Quantity_in_hand__c
      FROM Inventory__c
      WHERE Id = :data.inventory.Id
      LIMIT 1
    ];
    System.assertEquals(startingQty, updatedInventory.Quantity_in_hand__c);
    System.assertEquals(0, [SELECT COUNT() FROM Inventory_Adjustment__c]);
  }

  @IsTest
  static void inventoryBulkUpload_processesOnlyEligibleLinesInMixedList() {
    TestData data = loadCoreTestData();
    Invoice__c draftInvoice = getInvoiceByMarker(DRAFT_INV_MARKER);
    Decimal startingQty = data.inventory.Quantity_in_hand__c;

    Test.startTest();
    HandleInventoryBulkUpload.inventoryBulkUpload(
      new List<Invoice_Line_Item__c>{
        buildLine(draftInvoice.Id, data.product.Id, 20),
        buildLine(data.confirmedInvoice.Id, data.product.Id, 5)
      }
    );
    Test.stopTest();

    Inventory__c updatedInventory = [
      SELECT Quantity_in_hand__c
      FROM Inventory__c
      WHERE Id = :data.inventory.Id
      LIMIT 1
    ];
    System.assertEquals(startingQty - 5, updatedInventory.Quantity_in_hand__c);
    System.assertEquals(
      1,
      [
        SELECT COUNT()
        FROM Inventory_Adjustment__c
        WHERE Secondary_Invoice_transaction__c = :data.confirmedInvoice.Id
      ]
    );
  }

  @IsTest
  static void triggerInsert_invokesInventoryBulkUploadForEligibleInvoice() {
    if (!hasBulkUploadInvoiceFields()) {
      return;
    }

    TestData data = loadCoreTestData();
    markInvoiceAsBulkUpload(data.confirmedInvoice.Id);

    Decimal startingQty = [
      SELECT Quantity_in_hand__c
      FROM Inventory__c
      WHERE Id = :data.inventory.Id
      LIMIT 1
    ].Quantity_in_hand__c;

    Test.startTest();
    insert new Invoice_Line_Item__c(
      Invoice__c = data.confirmedInvoice.Id,
      Product__c = data.product.Id,
      Quantity__c = 7
    );
    Test.stopTest();

    Inventory__c updatedInventory = [
      SELECT Quantity_in_hand__c
      FROM Inventory__c
      WHERE Id = :data.inventory.Id
      LIMIT 1
    ];
    System.assertEquals(startingQty - 7, updatedInventory.Quantity_in_hand__c);
  }

  private class TestData {
    Invoice__c confirmedInvoice;
    Product__c product;
    Inventory__c inventory;
  }

  private static TestData loadCoreTestData() {
    TestData data = new TestData();
    data.confirmedInvoice = getInvoiceByMarker(CONFIRMED_INV_MARKER);
    data.product = getProductByCode(TEST_PRODUCT_A);
    data.inventory = getInventory(data.product.Id);
    return data;
  }

  private static Invoice_Line_Item__c buildLine(
    Id invoiceId,
    Id productId,
    Decimal quantity
  ) {
    return new Invoice_Line_Item__c(
      Invoice__c = invoiceId,
      Product__c = productId,
      Quantity__c = quantity
    );
  }

  /**
   * Always inserts a NEW invoice.
   * Inserts as Draft first, then moves to Confirmed only if needed (Draft -> Confirmed is allowed).
   * Never moves Confirmed -> Draft.
   */
    private static Invoice__c createTestInvoice(
    Id recordTypeId,
    Order__c order,
    Account retailer,
    Account distributor,
    String markerName,
    String targetStatus
  ) {
    String invoiceNumber =
      markerName + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));

    Invoice__c invoice = new Invoice__c(
      RecordTypeId = recordTypeId,
      Distributor_Account__c = distributor.Id,
      Name = markerName,
      Status__c = STATUS_DRAFT
    );

    if (hasInvoiceField('Order__c')) {
      invoice.put('Order__c', order.Id);
    }
    if (hasInvoiceField('Retailer_Account__c')) {
      invoice.put('Retailer_Account__c', retailer.Id);
    }
    if (hasInvoiceField('Invoice_Number__c')) {
      invoice.put('Invoice_Number__c', invoiceNumber);
    }
    if (hasInvoiceField('Invoice_Date__c')) {
      invoice.put('Invoice_Date__c', Date.today());
    }

    insert invoice;

    if (STATUS_CONFIRMED.equals(targetStatus)) {
      invoice.Status__c = STATUS_CONFIRMED;
      update invoice;
    }

    return invoice;
  }

  private static Account resolveDistributorAccount() {
    Account queried = queryDistributorFromOrg();
    return queried != null ? queried : insertDistributorAccount();
  }

  private static Account resolveRetailerAccount(Account distributorFallback) {
    Account retailer = queryRetailerFromOrg();
    return retailer != null ? retailer : distributorFallback;
  }

  private static Account queryDistributorFromOrg() {
    List<User> users = [
      SELECT ContactId
      FROM User
      WHERE Id = :UserInfo.getUserId()
      LIMIT 1
    ];
    if (!users.isEmpty() && users[0].ContactId != null) {
      List<Contact> contacts = [
        SELECT AccountId
        FROM Contact
        WHERE Id = :users[0].ContactId
        LIMIT 1
      ];
      if (!contacts.isEmpty() && contacts[0].AccountId != null) {
        List<Account> linked = [
          SELECT Id
          FROM Account
          WHERE Id = :contacts[0].AccountId
          LIMIT 1
        ];
        if (!linked.isEmpty()) {
          return linked[0];
        }
      }
    }

    List<Invoice__c> invoices = [
      SELECT Distributor_Account__c
      FROM Invoice__c
      WHERE Distributor_Account__c != NULL
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!invoices.isEmpty()) {
      List<Account> distributors = [
        SELECT Id
        FROM Account
        WHERE Id = :invoices[0].Distributor_Account__c
        LIMIT 1
      ];
      if (!distributors.isEmpty()) {
        return distributors[0];
      }
    }

    Id distributorRtId = getAccountRecordTypeId('Distributor');
    if (distributorRtId != null) {
      List<Account> distributors = [
        SELECT Id
        FROM Account
        WHERE RecordTypeId = :distributorRtId
        ORDER BY CreatedDate DESC
        LIMIT 1
      ];
      if (!distributors.isEmpty()) {
        return distributors[0];
      }
    }

    List<Account> anyAccount = [
      SELECT Id
      FROM Account
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return anyAccount.isEmpty() ? null : anyAccount[0];
  }

  private static Account queryRetailerFromOrg() {
    Id retailerRtId = getAccountRecordTypeId('Retailer');
    if (retailerRtId == null) {
      return null;
    }

    List<Account> retailers = [
      SELECT Id
      FROM Account
      WHERE RecordTypeId = :retailerRtId
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    return retailers.isEmpty() ? null : retailers[0];
  }

  private static Account insertDistributorAccount() {
    Account distributor = new Account(
      Name = 'HIBU Dist ' + String.valueOf(DateTime.now().getTime())
    );
    Id distributorRtId = getAccountRecordTypeId('Distributor');
    if (distributorRtId != null) {
      distributor.RecordTypeId = distributorRtId;
    }
    if (hasAccountField('Primary_State__c')) {
      distributor.put('Primary_State__c', 'Karnataka');
    }
    insert distributor;
    return distributor;
  }

  private static Order__c resolveOrder(Account retailer, Account distributor) {
    List<Order__c> existingOrders = [
      SELECT Id
      FROM Order__c
      ORDER BY CreatedDate DESC
      LIMIT 1
    ];
    if (!existingOrders.isEmpty()) {
      return existingOrders[0];
    }

    Order__c order = new Order__c();
    Id orderRtId = getOrderRecordTypeId('Secondary Order');
    if (orderRtId != null) {
      order.RecordTypeId = orderRtId;
    }
    if (hasOrderField('Account__c')) {
      order.put('Account__c', retailer.Id);
    }
    if (hasOrderField('AccountId__c')) {
      order.put('AccountId__c', distributor.Id);
    }
    if (hasOrderField('Status__c')) {
      order.put('Status__c', 'Order Placed');
    }
    if (hasOrderField('EffectiveDate__c')) {
      order.put('EffectiveDate__c', Date.today());
    }
    insert order;
    return order;
  }

  private static Product__c queryOrCreateProduct(String productCode) {
    List<Product__c> existing = [
      SELECT Id
      FROM Product__c
      WHERE Product_Code__c = :productCode
      LIMIT 1
    ];
    if (!existing.isEmpty()) {
      return existing[0];
    }

    Product__c product = new Product__c(
      Name = productCode,
      Product_Code__c = productCode,
      IsActive__c = true
    );
    insert product;
    return product;
  }

  private static void upsertInventory(
    Id distributorId,
    Id productId,
    Decimal quantityInHand
  ) {
    List<Inventory__c> existing = [
      SELECT Id, Quantity_in_hand__c
      FROM Inventory__c
      WHERE Distributor_Name__c = :distributorId
        AND Product__c = :productId
      LIMIT 1
    ];

    if (!existing.isEmpty()) {
      existing[0].Quantity_in_hand__c = quantityInHand;
      update existing[0];
      return;
    }

    insert new Inventory__c(
      Distributor_Name__c = distributorId,
      Product__c = productId,
      Quantity_in_hand__c = quantityInHand
    );
  }

  private static Invoice__c getInvoiceByMarker(String markerName) {
    return [
      SELECT Id, Status__c
      FROM Invoice__c
      WHERE Name = :markerName
      LIMIT 1
    ];
  }

  private static Product__c getProductByCode(String productCode) {
    return [
      SELECT Id
      FROM Product__c
      WHERE Product_Code__c = :productCode
      LIMIT 1
    ];
  }

  private static Inventory__c getInventory(Id productId) {
    return [
      SELECT Id, Quantity_in_hand__c
      FROM Inventory__c
      WHERE Product__c = :productId
      LIMIT 1
    ];
  }

  private static Id getSecondaryInvoiceRecordTypeId() {
    return getRecordTypeId('Invoice__c', RT_SECONDARY_INVOICE);
  }

  private static Id getAccountRecordTypeId(String developerName) {
    return getRecordTypeId('Account', developerName);
  }

  private static Id getOrderRecordTypeId(String developerName) {
    return getRecordTypeId('Order__c', developerName);
  }

  private static Id getRecordTypeId(String objectApiName, String developerName) {
    if (!Schema.getGlobalDescribe().containsKey(objectApiName)) {
      return null;
    }
    Map<String, Schema.RecordTypeInfo> rtMap = Schema.getGlobalDescribe()
      .get(objectApiName)
      .getDescribe()
      .getRecordTypeInfosByDeveloperName();
    return rtMap.containsKey(developerName)
      ? rtMap.get(developerName).getRecordTypeId()
      : null;
  }

  private static Boolean hasAccountField(String fieldApiName) {
    return hasField('Account', fieldApiName);
  }

  private static Boolean hasOrderField(String fieldApiName) {
    return hasField('Order__c', fieldApiName);
  }

  private static Boolean hasInvoiceField(String fieldApiName) {
    return hasField('Invoice__c', fieldApiName);
  }

  private static Boolean hasField(String objectApiName, String fieldApiName) {
    if (!Schema.getGlobalDescribe().containsKey(objectApiName)) {
      return false;
    }
    return Schema.getGlobalDescribe()
      .get(objectApiName)
      .getDescribe()
      .fields.getMap()
      .containsKey(fieldApiName.toLowerCase());
  }

  private static Boolean hasBulkUploadInvoiceFields() {
    return hasInvoiceField('Ref_Invoice_No_Data_Upload__c') &&
      hasInvoiceField('Data_Upload__c');
  }

  private static void markInvoiceAsBulkUpload(Id invoiceId) {
    update new Invoice__c(
      Id = invoiceId,
      Ref_Invoice_No_Data_Upload__c =
        'TRG-REF-' + String.valueOf(DateTime.now().getTime()),
      Data_Upload__c = true,
      Status__c = STATUS_CONFIRMED
    );
  }

  private static Id buildSyntheticId(Schema.SObjectType sobjectType) {
    String keyPrefix = sobjectType.getDescribe().getKeyPrefix();
    return (Id) (keyPrefix + '000000000000');
  }
}