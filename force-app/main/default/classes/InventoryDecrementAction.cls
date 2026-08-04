/**
 * Invocable Apex action that decrements Inventory__c.Quantity_On_Hand__c for the
 * products sold on a set of OpportunityLineItems.
 *
 * Called from the asynchronous path of the Record-Triggered Flow
 * `Opportunity_Closed_Won_Creates_Assets`, whose `Decrement_Inventory` element is
 * fault-connected. Any unrecoverable error is surfaced to that fault path as an
 * InventoryDecrementException so the Flow can log it.
 *
 * Bulk contract:
 *  - The Flow invokes this once per Opportunity, but Flow batches asynchronous
 *    interviews, so `requests` may contain many entries. Everything is aggregated
 *    across ALL requests before any query or DML runs.
 *  - Exactly one SOQL query and one DML statement per invocation, regardless of the
 *    number of requests or line items.
 *
 * Business rules (per approved design):
 *  - Quantity on hand is floored at zero and never goes negative.
 *  - A product with no matching Inventory__c record is skipped silently.
 *  - If duplicate Inventory__c records exist for the same product, only the record
 *    with the lowest Id is decremented; the others are left untouched.
 */
public with sharing class InventoryDecrementAction {
  /**
   * Thrown when the inventory decrement cannot be completed. Routed to the Flow's
   * fault connector on the `Decrement_Inventory` element.
   */
  public class InventoryDecrementException extends Exception {
  }

  /**
   * One request per Flow interview. `lineItems` carries the Product2Id and Quantity
   * sold for each OpportunityLineItem on the Closed Won Opportunity.
   */
  public class Request {
    @InvocableVariable(
      label='Opportunity Line Items'
      description='Line items whose products should be decremented from inventory.'
      required=true
    )
    public List<OpportunityLineItem> lineItems;
  }

  /**
   * Aggregates quantity sold per product across every request, then applies a single
   * bulk decrement to the matching Inventory__c records.
   *
   * @param requests one entry per Flow interview; may contain many entries when Flow
   *                 batches asynchronous interviews.
   */
  @InvocableMethod(
    label='Decrement Inventory for Line Items'
    description='Decrements Quantity On Hand on Inventory records for the products sold on the supplied Opportunity Line Items. Floors at zero and skips products with no Inventory record.'
    category='Inventory'
  )
  public static void decrement(List<Request> requests) {
    if (requests == null || requests.isEmpty()) {
      return;
    }

    Map<Id, Decimal> quantitySoldByProductId = aggregateQuantitySold(requests);
    if (quantitySoldByProductId.isEmpty()) {
      return;
    }

    applyDecrements(quantitySoldByProductId);
  }

  /**
   * Single pass over every line item in every request, summing Quantity by Product2Id.
   * Line items that are null, have no Product2Id, or have no Quantity contribute
   * nothing but do not stop processing.
   */
  private static Map<Id, Decimal> aggregateQuantitySold(
    List<Request> requests
  ) {
    Map<Id, Decimal> quantitySoldByProductId = new Map<Id, Decimal>();

    for (Request req : requests) {
      if (req == null || req.lineItems == null) {
        continue;
      }

      for (OpportunityLineItem lineItem : req.lineItems) {
        if (
          lineItem == null ||
          lineItem.Product2Id == null ||
          lineItem.Quantity == null
        ) {
          continue;
        }

        // OpportunityLineItem.Quantity is a Decimal in Apex (describe reports its
        // SOQL type as "double", but there is no Decimal.valueOf(Decimal) overload),
        // so assign it directly - no conversion is needed or possible.
        Decimal quantitySold = lineItem.Quantity;
        Decimal runningTotal = quantitySoldByProductId.get(lineItem.Product2Id);
        quantitySoldByProductId.put(
          lineItem.Product2Id,
          runningTotal == null ? quantitySold : runningTotal + quantitySold
        );
      }
    }

    return quantitySoldByProductId;
  }

  /**
   * One query for all affected inventory, one update for all changed records.
   */
  private static void applyDecrements(
    Map<Id, Decimal> quantitySoldByProductId
  ) {
    Map<Id, Inventory__c> inventoryByProductId = queryInventoryByProductId(
      quantitySoldByProductId.keySet()
    );

    List<Inventory__c> inventoryToUpdate = new List<Inventory__c>();

    for (Id productId : quantitySoldByProductId.keySet()) {
      Inventory__c inventory = inventoryByProductId.get(productId);
      if (inventory == null) {
        // No Inventory record for this product - skip silently by design.
        continue;
      }

      Decimal currentOnHand = inventory.Quantity_On_Hand__c == null
        ? 0
        : inventory.Quantity_On_Hand__c;
      Decimal newOnHand =
        currentOnHand - quantitySoldByProductId.get(productId);
      if (newOnHand < 0) {
        newOnHand = 0;
      }
      // Quantity_On_Hand__c is Number(18,2); round here so the stored value is
      // predictable rather than relying on implicit rounding on save.
      newOnHand = newOnHand.setScale(2, System.RoundingMode.HALF_UP);

      if (newOnHand == inventory.Quantity_On_Hand__c) {
        continue;
      }

      inventory.Quantity_On_Hand__c = newOnHand;
      inventoryToUpdate.add(inventory);
    }

    if (inventoryToUpdate.isEmpty()) {
      return;
    }

    try {
      Database.update(inventoryToUpdate, true, AccessLevel.USER_MODE);
    } catch (DmlException e) {
      throw new InventoryDecrementException(
        'Unable to decrement inventory: ' + e.getMessage(),
        e
      );
    }
  }

  /**
   * Returns the Inventory__c record to decrement for each product, keyed by product.
   * Ordering by Id ascending makes duplicate handling deterministic: the first record
   * encountered for a product is the lowest Id, and later duplicates are ignored.
   */
  private static Map<Id, Inventory__c> queryInventoryByProductId(
    Set<Id> productIds
  ) {
    Map<Id, Inventory__c> inventoryByProductId = new Map<Id, Inventory__c>();

    try {
      for (Inventory__c inventory : [
        SELECT Id, Product__c, Quantity_On_Hand__c
        FROM Inventory__c
        WHERE Product__c IN :productIds
        WITH USER_MODE
        ORDER BY Id ASC
      ]) {
        if (!inventoryByProductId.containsKey(inventory.Product__c)) {
          inventoryByProductId.put(inventory.Product__c, inventory);
        }
      }
    } catch (QueryException e) {
      throw new InventoryDecrementException(
        'Unable to read inventory records: ' + e.getMessage(),
        e
      );
    }

    return inventoryByProductId;
  }
}
