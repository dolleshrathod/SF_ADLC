/**
 * Tests for InventoryDecrementAction.
 *
 * Data strategy: OpportunityLineItem records passed into the invocable action are built
 * in memory (never inserted). The class under test never queries OpportunityLineItem -
 * it only reads Product2Id/Quantity off whatever list the Flow (or this test) hands it -
 * so constructing them in memory keeps bulk scenarios fast and avoids needing
 * Opportunity/PricebookEntry setup that the class does not depend on.
 *
 * Product2 and Inventory__c records ARE inserted because the class queries and updates
 * Inventory__c for real, WITH USER_MODE.
 */
@isTest
private class InventoryDecrementActionTest {
  private static final String PRODUCT_NORMAL = 'Widget - Normal';
  private static final String PRODUCT_FLOOR = 'Widget - Floor';
  private static final String PRODUCT_DUPLICATE = 'Widget - Duplicate Inventory';
  private static final String PRODUCT_NO_INVENTORY = 'Widget - No Inventory';
  private static final String PRODUCT_ALREADY_ZERO = 'Widget - Already Zero';

  @TestSetup
  static void makeData() {
    // Guarantee USER_MODE access to Inventory__c for whichever user runs these tests,
    // regardless of the deploying user's profile. Wrapped in System.runAs() so this
    // setup-object DML doesn't collide with the Product2/Inventory__c DML below
    // (Mixed DML Operation).
    grantInventoryAccessToCurrentUser();

    List<Product2> products = new List<Product2>{
      new Product2(Name = PRODUCT_NORMAL, IsActive = true),
      new Product2(Name = PRODUCT_FLOOR, IsActive = true),
      new Product2(Name = PRODUCT_DUPLICATE, IsActive = true),
      new Product2(Name = PRODUCT_NO_INVENTORY, IsActive = true),
      new Product2(Name = PRODUCT_ALREADY_ZERO, IsActive = true)
    };
    insert products;

    Map<String, Id> productIdByName = new Map<String, Id>();
    for (Product2 p : products) {
      productIdByName.put(p.Name, p.Id);
    }

    insert new List<Inventory__c>{
      new Inventory__c(
        Product__c = productIdByName.get(PRODUCT_NORMAL),
        Quantity_On_Hand__c = 100
      ),
      new Inventory__c(
        Product__c = productIdByName.get(PRODUCT_FLOOR),
        Quantity_On_Hand__c = 10
      ),
      new Inventory__c(
        Product__c = productIdByName.get(PRODUCT_ALREADY_ZERO),
        Quantity_On_Hand__c = 0
      )
      // PRODUCT_NO_INVENTORY intentionally has no Inventory__c record.
    };

    // Two separate insert statements so the first is guaranteed the lower Id -
    // required to make the "lowest Id wins" scenario deterministic.
    insert new Inventory__c(
      Product__c = productIdByName.get(PRODUCT_DUPLICATE),
      Quantity_On_Hand__c = 50
    );
    insert new Inventory__c(
      Product__c = productIdByName.get(PRODUCT_DUPLICATE),
      Quantity_On_Hand__c = 999
    );
  }

  @isTest
  static void testDecrementReducesQuantityOnHand() {
    Id productId = productIdByName(PRODUCT_NORMAL);
    InventoryDecrementAction.Request req = buildRequest(
      new List<OpportunityLineItem>{ buildLineItem(productId, 30) }
    );

    Test.startTest();
    InventoryDecrementAction.decrement(
      new List<InventoryDecrementAction.Request>{ req }
    );
    Test.stopTest();

    Inventory__c updated = inventoryByProduct(productId);
    Assert.areEqual(
      70.00,
      updated.Quantity_On_Hand__c,
      'Selling 30 of 100 on-hand units should leave 70 on hand.'
    );
  }

  @isTest
  static void testDecrementFloorsAtZeroWhenSoldExceedsOnHand() {
    Id productId = productIdByName(PRODUCT_FLOOR);
    InventoryDecrementAction.Request req = buildRequest(
      new List<OpportunityLineItem>{ buildLineItem(productId, 25) }
    );

    Test.startTest();
    InventoryDecrementAction.decrement(
      new List<InventoryDecrementAction.Request>{ req }
    );
    Test.stopTest();

    Inventory__c updated = inventoryByProduct(productId);
    Assert.areEqual(
      0.00,
      updated.Quantity_On_Hand__c,
      'Selling 25 of 10 on-hand units must floor at zero, never go negative.'
    );
  }

  @isTest
  static void testAggregatesMultipleLineItemsAcrossRequests() {
    Id productId = productIdByName(PRODUCT_NORMAL);
    InventoryDecrementAction.Request req1 = buildRequest(
      new List<OpportunityLineItem>{
        buildLineItem(productId, 12.5),
        buildLineItem(productId, 7.5)
      }
    );
    InventoryDecrementAction.Request req2 = buildRequest(
      new List<OpportunityLineItem>{ buildLineItem(productId, 10) }
    );

    Test.startTest();
    InventoryDecrementAction.decrement(
      new List<InventoryDecrementAction.Request>{ req1, req2 }
    );
    Test.stopTest();

    Inventory__c updated = inventoryByProduct(productId);
    Assert.areEqual(
      70.00,
      updated.Quantity_On_Hand__c,
      'Two line items in one request (12.5 + 7.5) plus one line item in a second ' +
      'request (10) must aggregate to 30 sold and decrement 100 down to 70 in a single call.'
    );
  }

  @isTest
  static void testProductWithNoInventoryRecordIsSkippedSilently() {
    Id missingProductId = productIdByName(PRODUCT_NO_INVENTORY);
    Id normalProductId = productIdByName(PRODUCT_NORMAL);
    InventoryDecrementAction.Request req = buildRequest(
      new List<OpportunityLineItem>{
        buildLineItem(missingProductId, 5),
        buildLineItem(normalProductId, 10)
      }
    );

    Test.startTest();
    try {
      InventoryDecrementAction.decrement(
        new List<InventoryDecrementAction.Request>{ req }
      );
    } catch (Exception e) {
      Assert.fail(
        'A product with no Inventory__c record must be skipped silently, not throw: ' +
        e.getMessage()
      );
    }
    Test.stopTest();

    List<Inventory__c> stillNone = [
      SELECT Id
      FROM Inventory__c
      WHERE Product__c = :missingProductId
    ];
    Assert.areEqual(
      0,
      stillNone.size(),
      'No Inventory__c record should ever be created for a product that has none.'
    );

    Inventory__c normalUpdated = inventoryByProduct(normalProductId);
    Assert.areEqual(
      90.00,
      normalUpdated.Quantity_On_Hand__c,
      'The product that does have inventory must still decrement even when another ' +
      'product in the same call has no matching Inventory__c record.'
    );
  }

  @isTest
  static void testDuplicateInventoryRecordsOnlyLowestIdDecremented() {
    Id productId = productIdByName(PRODUCT_DUPLICATE);
    List<Inventory__c> beforeRecords = inventoriesByProduct(productId);
    Assert.areEqual(
      2,
      beforeRecords.size(),
      'Test setup should have created two Inventory__c records for the duplicate-product scenario.'
    );
    Id lowestId = beforeRecords[0].Id;
    Id highestId = beforeRecords[1].Id;

    InventoryDecrementAction.Request req = buildRequest(
      new List<OpportunityLineItem>{ buildLineItem(productId, 20) }
    );

    Test.startTest();
    InventoryDecrementAction.decrement(
      new List<InventoryDecrementAction.Request>{ req }
    );
    Test.stopTest();

    Map<Id, Inventory__c> afterById = new Map<Id, Inventory__c>(
      [
        SELECT Id, Quantity_On_Hand__c
        FROM Inventory__c
        WHERE Id IN :new List<Id>{ lowestId, highestId }
      ]
    );
    Assert.areEqual(
      30.00,
      afterById.get(lowestId).Quantity_On_Hand__c,
      'The lowest-Id duplicate Inventory__c record must absorb the full decrement (50 - 20 = 30).'
    );
    Assert.areEqual(
      999.00,
      afterById.get(highestId).Quantity_On_Hand__c,
      'The higher-Id duplicate Inventory__c record must be left completely untouched.'
    );
  }

  @isTest
  static void testNoOpWhenInventoryAlreadyAtZero() {
    Id productId = productIdByName(PRODUCT_ALREADY_ZERO);
    InventoryDecrementAction.Request req = buildRequest(
      new List<OpportunityLineItem>{ buildLineItem(productId, 15) }
    );

    Test.startTest();
    Integer dmlBefore = Limits.getDmlStatements();
    InventoryDecrementAction.decrement(
      new List<InventoryDecrementAction.Request>{ req }
    );
    Integer dmlAfter = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(
      0,
      dmlAfter - dmlBefore,
      'When the computed new on-hand value equals the current value (0 stays 0), no DML should run at all.'
    );

    Inventory__c updated = inventoryByProduct(productId);
    Assert.areEqual(
      0.00,
      updated.Quantity_On_Hand__c,
      'On-hand quantity that is already zero must remain zero, never negative.'
    );
  }

  @isTest
  static void testBulkVolumeUsesSingleQueryAndSingleDmlStatement() {
    List<Product2> bulkProducts = new List<Product2>();
    for (Integer i = 0; i < 12; i++) {
      bulkProducts.add(
        new Product2(Name = 'Bulk Widget ' + i, IsActive = true)
      );
    }
    insert bulkProducts;

    List<Inventory__c> bulkInventory = new List<Inventory__c>();
    for (Product2 p : bulkProducts) {
      bulkInventory.add(
        new Inventory__c(Product__c = p.Id, Quantity_On_Hand__c = 100000)
      );
    }
    insert bulkInventory;

    // 4 Flow interviews (requests) x 50 line items each = 200 total line items,
    // cycled evenly across the 12 products - proves aggregation and the
    // single-SOQL/single-DML contract hold regardless of request or line-item volume.
    Integer requestCount = 4;
    Integer lineItemsPerRequest = 50;
    List<InventoryDecrementAction.Request> requests = new List<InventoryDecrementAction.Request>();
    Map<Id, Decimal> expectedSoldByProduct = new Map<Id, Decimal>();

    for (Integer r = 0; r < requestCount; r++) {
      List<OpportunityLineItem> lineItems = new List<OpportunityLineItem>();
      for (Integer i = 0; i < lineItemsPerRequest; i++) {
        Id productId = bulkProducts[Math.mod(i, bulkProducts.size())].Id;
        Decimal qty = 5;
        lineItems.add(buildLineItem(productId, qty));
        Decimal runningTotal = expectedSoldByProduct.containsKey(productId)
          ? expectedSoldByProduct.get(productId)
          : 0;
        expectedSoldByProduct.put(productId, runningTotal + qty);
      }
      requests.add(buildRequest(lineItems));
    }

    Test.startTest();
    Integer queriesBefore = Limits.getQueries();
    Integer dmlBefore = Limits.getDmlStatements();
    InventoryDecrementAction.decrement(requests);
    Integer queriesAfter = Limits.getQueries();
    Integer dmlAfter = Limits.getDmlStatements();
    Test.stopTest();

    Assert.areEqual(
      1,
      queriesAfter - queriesBefore,
      'Exactly one SOQL query must be issued no matter how many requests/line items are supplied (200 line items across 4 requests here).'
    );
    Assert.areEqual(
      1,
      dmlAfter - dmlBefore,
      'Exactly one DML statement must be issued no matter how many requests/line items are supplied (200 line items across 4 requests here).'
    );

    Map<Id, Inventory__c> updatedByProduct = new Map<Id, Inventory__c>();
    for (Inventory__c inv : [
      SELECT Id, Product__c, Quantity_On_Hand__c
      FROM Inventory__c
      WHERE Product__c IN :bulkProducts
    ]) {
      updatedByProduct.put(inv.Product__c, inv);
    }
    for (Id productId : expectedSoldByProduct.keySet()) {
      Decimal expected = (100000 - expectedSoldByProduct.get(productId))
        .setScale(2);
      Assert.areEqual(
        expected,
        updatedByProduct.get(productId).Quantity_On_Hand__c,
        'Aggregated bulk decrement for product ' +
          productId +
          ' did not match the expected on-hand value.'
      );
    }
  }

  @isTest
  static void testNullAndEmptyInputsAreHandledWithoutError() {
    Id productId = productIdByName(PRODUCT_NORMAL);

    OpportunityLineItem itemMissingProduct = new OpportunityLineItem(
      Quantity = 5
    );
    OpportunityLineItem itemMissingQuantity = new OpportunityLineItem(
      Product2Id = productId
    );

    InventoryDecrementAction.Request requestWithNullLineItems = new InventoryDecrementAction.Request();
    requestWithNullLineItems.lineItems = null;

    InventoryDecrementAction.Request requestWithMixedInvalidItems = buildRequest(
      new List<OpportunityLineItem>{
        itemMissingProduct,
        itemMissingQuantity,
        null
      }
    );

    Test.startTest();
    try {
      InventoryDecrementAction.decrement(null);
      InventoryDecrementAction.decrement(
        new List<InventoryDecrementAction.Request>()
      );
      InventoryDecrementAction.decrement(
        new List<InventoryDecrementAction.Request>{
          null,
          requestWithNullLineItems,
          requestWithMixedInvalidItems
        }
      );
    } catch (Exception e) {
      Assert.fail(
        'Null requests list, empty requests list, a null request, a request with null ' +
          'lineItems, and line items missing Product2Id/Quantity must all be handled ' +
          'gracefully, not throw: ' +
          e.getMessage()
      );
    }
    Test.stopTest();

    Inventory__c unchanged = inventoryByProduct(productId);
    Assert.areEqual(
      100.00,
      unchanged.Quantity_On_Hand__c,
      'None of the supplied inputs carry a usable Product2Id + Quantity pair, so inventory must remain unchanged.'
    );
  }

  @isTest
  static void testInsufficientAccessThrowsInventoryDecrementException() {
    Id productId = productIdByName(PRODUCT_NORMAL);
    User restrictedUser = createUserWithoutInventoryAccess();

    InventoryDecrementAction.Request req = buildRequest(
      new List<OpportunityLineItem>{ buildLineItem(productId, 10) }
    );

    Test.startTest();
    System.runAs(restrictedUser) {
      try {
        InventoryDecrementAction.decrement(
          new List<InventoryDecrementAction.Request>{ req }
        );
        Assert.fail(
          'A user with no object/field access to Inventory__c must fail the WITH ' +
          'USER_MODE query, which the class should surface as InventoryDecrementException.'
        );
      } catch (InventoryDecrementAction.InventoryDecrementException e) {
        Assert.isTrue(
          e.getMessage().startsWith('Unable to read inventory records'),
          'Expected the query-stage failure message from queryInventoryByProductId, got: ' +
          e.getMessage()
        );
      }
    }
    Test.stopTest();
  }

  // ---------------------------------------------------------------------------------
  // Test data helpers
  // ---------------------------------------------------------------------------------

  private static InventoryDecrementAction.Request buildRequest(
    List<OpportunityLineItem> lineItems
  ) {
    InventoryDecrementAction.Request req = new InventoryDecrementAction.Request();
    req.lineItems = lineItems;
    return req;
  }

  private static OpportunityLineItem buildLineItem(
    Id productId,
    Decimal quantity
  ) {
    return new OpportunityLineItem(Product2Id = productId, Quantity = quantity);
  }

  private static Id productIdByName(String name) {
    return [SELECT Id FROM Product2 WHERE Name = :name LIMIT 1].Id;
  }

  private static Inventory__c inventoryByProduct(Id productId) {
    return [
      SELECT Id, Product__c, Quantity_On_Hand__c
      FROM Inventory__c
      WHERE Product__c = :productId
      ORDER BY Id ASC
      LIMIT 1
    ];
  }

  private static List<Inventory__c> inventoriesByProduct(Id productId) {
    return [
      SELECT Id, Product__c, Quantity_On_Hand__c
      FROM Inventory__c
      WHERE Product__c = :productId
      ORDER BY Id ASC
    ];
  }

  /**
   * Assigns the InventoryAccess permission set (CRUD + FLS on Inventory__c) to the
   * user running the tests, so the class's WITH USER_MODE / AccessLevel.USER_MODE
   * checks succeed on the happy-path tests regardless of the deploying user's profile.
   * Wrapped in System.runAs() to avoid a Mixed DML Operation error against the
   * Product2/Inventory__c inserts that follow in the same @TestSetup transaction.
   */
  private static void grantInventoryAccessToCurrentUser() {
    List<PermissionSet> inventoryAccessSets = [
      SELECT Id
      FROM PermissionSet
      WHERE Name = 'InventoryAccess'
      LIMIT 1
    ];
    if (inventoryAccessSets.isEmpty()) {
      return;
    }

    Id currentUserId = UserInfo.getUserId();
    List<PermissionSetAssignment> existingAssignments = [
      SELECT Id
      FROM PermissionSetAssignment
      WHERE
        AssigneeId = :currentUserId
        AND PermissionSetId = :inventoryAccessSets[0].Id
    ];
    if (existingAssignments.isEmpty()) {
      System.runAs(new User(Id = currentUserId)) {
        insert new PermissionSetAssignment(
          AssigneeId = currentUserId,
          PermissionSetId = inventoryAccessSets[0].Id
        );
      }
    }
  }

  /**
   * Standard User profile with no InventoryAccess permission set assignment. Custom
   * objects deployed via metadata (like Inventory__c) grant no access to this profile
   * by default, so this user realistically triggers the WITH USER_MODE access failure
   * that queryInventoryByProductId() catches and rethrows as InventoryDecrementException.
   */
  private static User createUserWithoutInventoryAccess() {
    Profile standardProfile = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Standard User'
      LIMIT 1
    ];
    String uniqueSuffix =
      UserInfo.getOrganizationId() +
      '.' +
      String.valueOf(DateTime.now().getTime());
    User restrictedUser = new User(
      FirstName = 'Inventory',
      LastName = 'RestrictedTestUser',
      Alias = 'invres',
      Email = 'inventory.restricted.testuser@example.invalid',
      Username = 'inventory.restricted.testuser.' +
        uniqueSuffix +
        '@example.invalid',
      TimeZoneSidKey = 'America/Los_Angeles',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = standardProfile.Id,
      IsActive = true
    );
    insert restrictedUser;
    return restrictedUser;
  }
}
