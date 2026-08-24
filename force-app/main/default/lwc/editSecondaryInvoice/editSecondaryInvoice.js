import { LightningElement, track, api, wire } from 'lwc';
import createInvoiceData from '@salesforce/apex/EditSecondaryInvoiceHandler.createInvoiceData';
import getProductName from '@salesforce/apex/EditSecondaryInvoiceHandler.getProductName';
import getPriceByProduct from '@salesforce/apex/EditSecondaryInvoiceHandler.getPriceByProduct';
import getPriceForProduct from '@salesforce/apex/CounterInvoiceController.getPriceForProduct';
import getMRPByProduct from '@salesforce/apex/EditSecondaryInvoiceHandler.getMRPByProduct';
import getStockByProducts from '@salesforce/apex/EditSecondaryInvoiceHandler.getStockByProducts';
import saveInvoiceAndItems from '@salesforce/apex/EditSecondaryInvoiceHandler.saveInvoiceAndLineItems';
import getProductsWithStock from '@salesforce/apex/SecondaryInvoiceHandler.getProductsWithStock';
import INVOICE_HSN_LABEL from '@salesforce/label/c.Invoice_HSN';
import { isNullEmptyUndefined, isNullEmptyUndefinedObject, showToast } from 'c/dmsUtility';
import { NavigationMixin } from 'lightning/navigation';
import getqualitySchemeFromOrder from '@salesforce/apex/EditSecondaryInvoiceHandler.getqualitySchemeFromOrder';
import applyQuantitySchemeFromOrder from '@salesforce/apex/EditSecondaryInvoiceHandler.applyQuantitySchemeFromOrder';
import getvalueSchemeFromOrder from '@salesforce/apex/EditSecondaryInvoiceHandler.getvalueSchemeFromOrder';
// FIXED (2026-08-22): getAppliedValueScheme(String) only reads Scheme__c.Discount_Amount__c/
// Discount_Percentage__c directly — blank for a Flat Discount scheme (discount lives on
// Scheme_Slab__c), so Apply silently gave a 0 discount. getAppliedValueSchemeForOrder
// resolves the ACTUAL Scheme_Slab__c-based discount, mirroring secondaryInvoice.js's fix
// (decision log §8.4).
import getAppliedValueSchemeForOrder from '@salesforce/apex/EditSecondaryInvoiceHandler.getAppliedValueSchemeForOrder';
import getActiveSchemes from '@salesforce/apex/MultiSchemeReimbursementService.getActiveSchemes';
import saveAppliedLines from '@salesforce/apex/MultiSchemeReimbursementService.saveAppliedLines';
import getAppliedLinesForInvoice from '@salesforce/apex/MultiSchemeReimbursementService.getAppliedLinesForInvoice';
import getAppliedValueSchemeName from '@salesforce/apex/SchemeEvaluationService.getAppliedValueSchemeName';
import getProductForValueScheme from '@salesforce/apex/SchemeEvaluationService.getProductForValueScheme';
import NO_Cart_SCHEME_AVAILABLE from '@salesforce/label/c.No_Cart_Value_Scheme';
import getFreeOfferMessageForProducts from '@salesforce/apex/ModernTradeSchemeService.getFreeOfferMessageForProducts';


export default class EditSecondaryInvoice extends NavigationMixin(LightningElement) {

  @track dmsUserInfo = {};
  @track disAccountName;
  @track disBillingAddress;
  @track dmsuserPhone;
  @track dmsuserFSSAI;
  @track retailerInfo = {};
  @track invoiceInfo = {};
  @track invoiceLineItemsInfo = [];
  originalItemList = [];
  @track itemList;
  deletedItemIds = [];

  @track recordId;
  @track isCounterFlow = false;
  @track priceType = 'MRP';
  @track freeOfferMessage = null;

  @api invoice;
  @api invoiceLineItems;
  @api invoiceFound = false;
  @track isSaving = false;
  @track isProductSaving = false;

  initialized = false;
  isLoading = false;
  readMode = false;
  showModal = false;
  rowIndex;
  rowAction;
  iliEdit = false;
  iliProduct;
  iliQuantity;
  iliPrice;
  iliStockInHand;
  @track iliSkuDiscountPercent = 0;
  @track totalDisPercent = 0;
  @track totalDiscount = 0;
  @track totalDiscount1 = 0;
  @track totalDiscount2 = 0;
  @track lastValidInvoiceDate;
  @track roundOff = 0;
  @track originalInvoiceDate;

  searchQuery = '';
  productResults = [];
  selectedProduct = null;
  showDropdown = false;
  searchDebounce;
  searchDebounceTime = 300;

  @track searchBy = 'Name';
  @track searchByDisplayText = 'Name';
  @track showSearchByDropdown = false;

  @track valueSchemeThreshold = 0;
  @track activeProductId;
  selectedSchemeId;
  isCartContext = false;
  @track isQualityScheme = false;
  @track isValueScheme = false;
  @track schemeDetails = [];
  @track valueSchemeDetails = [];
  @track isNoSchemesMessage = false;
  @track noSchemesMessage = '';
  @track discountAmountGiven = 0;
  @track discountAmountGivenCheck = false;
  @track discountPercemtageGiven = 0;
  // The pre-tax subtotal a % Value Scheme discount is actually computed against — the
  // matched Product/Brand lines' subtotal for a scoped Flat Discount scheme, or null for a
  // global/non-scoped scheme (falls back to the whole taxable/cart total). Mirrors
  // secondaryInvoice.js — see decision log §8.6/§8.13.
  @track valueSchemeQualifyingSubtotal = null;
  @track valueSchemFinalId = '';
  @track ValueSchemeFinalName = '';
  @track ValueSchemeExist = false;
  @track grossCartTotal = 0;
  @track skipValueSchemeValidationOnce = false;

  // ── Multi-Scheme Retailer Reimbursement ────────────────────────────────
  @track activeSchemes = [];
@track netPayable = 0;
  @track isReimbursementDialog = false;

  _baseColumns = [
  { label: "#", fieldName: "rowNo", type: "text", readonly: true, initialWidth: 10, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "Item Description", fieldName: "ProductName", type: "text", wrapText: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "HSN", fieldName: "hsn", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "Stock In Hand", fieldName: "CurrentStock", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "Quantity", fieldName: "Quantity__c", type: "text", cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "MRP", fieldName: "mrp", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  // Rate/Amount are bound to displayPrice__c/displayTotalAmount__c rather than the raw
  // Price__c/Total_Amount__c — for Counter Invoice + MRP these show the tax-EXCLUDED
  // value (so Amount lines up with Taxable Amount below), computed in
  // handlePriceCalculations(). Neither column is inline-editable here — display-only,
  // doesn't affect what actually gets saved to Invoice_Line_Item__c.
  { label: "Rate", fieldName: "displayPrice__c", type: "text", cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "Amount", fieldName: "displayTotalAmount__c", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { label: "TOD", fieldName: "discount1Amt", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  // Purchase Quantity Discount scheme amount for this line (₹ only, no scheme name —
  // the name stays available via Quantity_Scheme_Applied__r.Name but isn't surfaced
  // in this column per requirement). Positioned right after TOD.
  { label: "Scheme", fieldName: "schemeDiscountAmt", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  // Same displayXxx pattern as Rate/Amount above — discount2Amt (raw, saved to
  // Discount_2__c) is untouched; displayDiscount2Amt is the tax-extracted value shown
  // for Counter Invoice + MRP so it lines up with the extracted Amount column.
  { label: "Dis2", fieldName: "displayDiscount2Amt", type: "text", readonly: true, cellAttributes: { style: { fieldName: 'quantityCellClass' } } },
  { type: "button-icon", typeAttributes: { iconName: "utility:edit", name: "edit", disabled: { fieldName: 'isPromotional' } }, fixedWidth: 40 },
  { type: "button-icon", typeAttributes: { iconName: "utility:add", name: "add", iconClass: "slds-icon-text-success", disabled: { fieldName: 'isPromotional' } }, fixedWidth: 40 },
  { type: "button-icon", typeAttributes: { iconName: "utility:percent", name: "scheme", title: "Apply Quantity Scheme", iconClass: "slds-icon-text-success", disabled: { fieldName: 'isPromotional' } }, fixedWidth: 40 },
  { type: "button-icon", typeAttributes: { iconName: "utility:delete", name: "delete", iconClass: "slds-icon-text-error", disabled: { fieldName: 'hasPromoChild' }, title: { fieldName: 'deleteTooltip' } }, fixedWidth: 40 }];

  // Counter Orders don't use TOD (Trade Offer Discount) or Purchase Quantity Discount
  // schemes — hide both columns when in the Counter flow rather than maintaining a
  // second hard-coded column array.
  get __columns() {
    if (this.isCounterFlow) {
      return this._baseColumns.filter((col) => col.label !== "TOD" && col.label !== "Scheme");
    }
    // Most invoices never use a Purchase Quantity Discount scheme — hide the "Scheme"
    // column entirely (not just show zeros) unless at least one line actually has one,
    // to keep the datatable from getting needlessly crowded.
    if (!this.hasSchemeDiscount) {
      return this._baseColumns.filter((col) => col.label !== "Scheme");
    }
    return this._baseColumns;
  }

  get skuDiscountActive() {
    return (this.itemList || []).some((i) => Number(i.SKU_Discount_Percent__c) > 0);
  }
  get overallDiscountActive() {
    return Number(this.invoiceInfo.Discount_2__c) > 0;
  }
  get hasSchemeDiscount() {
    return (this.itemList || []).some((item) => Number(item.schemeDiscountAmt) > 0);
  }

  // Display-only total for the "Discount Total" row — totalDiscount itself never included
  // the Value Scheme discount (that's applied as a separate later step in
  // handlePriceCalculations()'s taxable-value math). Mirrors secondaryInvoice.js's fix
  // (decision log §8.4 #4) so this row matches what's actually deducted from Taxable Value.
  get displayDiscountTotal() {
    const lineDiscounts = Number(this.totalDiscount) || 0;
    const valueSchemeDiscount = this.ValueSchemeExist
      ? Number(this.invoiceInfo?.Value_Scheme_Discount__c) || 0
      : 0;
    return this.roundNum(lineDiscounts + valueSchemeDiscount);
  }


  connectedCallback() {
    const queryParams = new URLSearchParams(window.location.search);
    this.recordId = queryParams.get('recordId');

    if (this.recordId) {
      this.getInvoiceData();
    } else {
      this.showErrorPopup('No record ID provided in the URL.');
    }
  }

  disconnectedCallback() {
    if (this.handleClickOutside) {
      document.removeEventListener('click', this.handleClickOutside);
    }
  }

  getInvoiceData() {
    this.isLoading = true;


    createInvoiceData({ invoiceId: this.recordId }).
    then((result) => {

      // Restore applied value scheme from invoice
      this.valueSchemFinalId = result.valueSchemeId;
      this.ValueSchemeExist = !!result.valueSchemeId;
      this.ValueSchemeFinalName = result.valueSchemeName;
      this.valueSchemeDiscount = result.valueSchemeDiscount;

      if (isNullEmptyUndefinedObject(result)) {

        this.dispatchEvent(showToast('Error', 'Error while creating invoice, missing either of required details Order/Retailer/Order Line items!', [], 'error', 'sticky'));
        this.dispatchEvent(new CustomEvent('cancelled', { detail: { 'message': 'Operation Cancelled' } }));
        this.navigateToRecordPage();
      } else if (Object.hasOwn(result, 'message') && result.message != 'Success') {

        this.dispatchEvent(showToast('Error', result.message, [], 'error', 'sticky'));
        this.dispatchEvent(new CustomEvent('cancelled', { detail: { 'message': 'Operation Cancelled' } }));
        this.navigateToRecordPage();
     } else {
        this.lastValidInvoiceDate = result.orderDate;

        // Sale_Type__c / Price_Type__c are real fields on Order__c, set for both Counter
        // Orders and regular DMS Secondary Orders. Trust whatever is actually stored,
        // regardless of order type — only fall back to 'MRP' if it's genuinely blank.
        // (Previously this was gated to Counter Orders only, so every regular Secondary
        // Order silently displayed/priced as MRP even when Dealer Price was stored.)
        this.isCounterFlow = result.invoice?.Order__r?.Type__c === 'Counter Order';
        this.priceType = result.invoice?.Order__r?.Price_Type__c || 'MRP';


        this.dmsUserInfo = Object.assign(result.dmsUser);
        this.disAccountName = this.dmsUserInfo?.Contact?.Account?.Name;
        const account = this.dmsUserInfo?.Contact?.Account;
        const addressParts = [
        account?.BillingStreet,
        account?.BillingCity,
        account?.BillingState,
        account?.BillingPostalCode,
        account?.BillingCountry].
        filter((part) => part);
        this.dmsuserPhone = account.Phone_1__c;
        this.dmsuserFSSAI = account.FSSAI__c;
        this.disBillingAddress = addressParts.join(', ');
        this.retailerInfo = Object.assign(result.retailerAccount);


        this.constructInvoiceData(result);


      }
    }).catch((error) => {
      this.dispatchEvent(showToast('Error', error.body.message, [], 'error', ''));
      this.dispatchEvent(new CustomEvent('cancelled', { detail: { 'message': 'Operation Cancelled' } }));
    }).finally(() => {
      this.isLoading = false;
    });
  }

  constructInvoiceData(data) {
    this.invoiceInfo = Object.assign(data.invoice);


    this.originalInvoiceDate = this.invoiceInfo.Invoice_Date__c;


    this.valueSchemFinalId = this.invoiceInfo.Value_Scheme_Applied__c || data.valueSchemeId;
    this.ValueSchemeExist = !!this.valueSchemFinalId;
    if (this.ValueSchemeExist && data.valueSchemeDiscount > 0) {
      this.discountAmountGiven = data.valueSchemeDiscount;
      this.discountAmountGivenCheck = true;
    }
    if (this.ValueSchemeExist) {
      this.getAppliedValueSchemeNameMethod();
      // NOTE: restoreValueSchemeThreshold() is NOT called here — this.itemList isn't
      // populated yet at this point in constructInvoiceData() (it's built further below),
      // so buildCartLinesForInvoice() would send Apex an empty cart-lines list. For a
      // scoped Flat Discount scheme that means no line matches, Apex returns no
      // discount/qualifyingSubtotal, and this method's own guards leave the STALE
      // discountAmountGivenCheck/discountAmountGiven set above untouched — so the invoice
      // silently keeps showing whatever (possibly wrong, pre-fix) rupee amount was last
      // persisted. Called instead at the end of this function, after itemList is ready —
      // see decision log, 2026-08-22.
    }

    
   // ── Multi-Scheme Retailer Reimbursement — fetch active schemes + restore previously applied ──
    if (this.retailerInfo?.Id) {
      getActiveSchemes({ retailerAccountId: this.retailerInfo.Id }).then((schemes) => {
        const activeList = (schemes || []).map((s) => ({
          allocationId: s.allocationId,
          schemeName: s.schemeName,
          balance: s.balance,
          // "CR/DR (HSU)" auto-applies up to its balance — no manual
          // selection needed. Every other scheme still requires the
          // distributor to pick it via the Reimbursement dialog.
          isApplied: s.schemeName === 'CR/DR (HSU)',
          amountApplied: 0
        }));
        if (this.invoiceInfo?.Id) {
          getAppliedLinesForInvoice({ invoiceId: this.invoiceInfo.Id }).then((appliedMap) => {
            this.activeSchemes = activeList.map((s) => {
              const previouslyApplied = appliedMap && appliedMap[s.allocationId] !== undefined;
              return previouslyApplied
                ? { ...s, isApplied: true, amountApplied: Number(appliedMap[s.allocationId]) || 0 }
                : s;
            });
            this.handlePriceCalculations();
          }).catch(() => { this.activeSchemes = activeList; this.handlePriceCalculations(); });
        } else {
          this.activeSchemes = activeList;
          this.handlePriceCalculations();
        }
      }).catch(() => { this.activeSchemes = []; });
    }

    this.invoiceLineItemsInfo = Object.assign(data.invoiceItems);
    this.itemList = this.invoiceLineItemsInfo.map((element) => ({ ...element }));

    let totalDis1 = 0;
    let totalDis2 = 0;
    let totalDis3 = 0;

    this.itemList.forEach((element, index) => {
      element.rowNo = index + 1;
      element.hsn = INVOICE_HSN_LABEL;
      element.mrp = element.MRP__c;
      element.isPromotional = element.Is_Promotional__c === true;
      element.selectedSchemeId = element.Quantity_Scheme_Applied__c || null;
      element.promoMinQty = element.Promo_Min_Qty__c;
      element.parentProductId = element.Parent_Product__c;
      if (element.isPromotional && !element.selectedSchemeId) {
        element.promoType = 'VALUE';
      }

      element.CurrentStock = data.stockByProduct?.[element.Product__c] || 0;
      const quantity = parseFloat(element.Quantity__c) || 0;
      const stock = parseFloat(element.CurrentStock) || 0;
      element.quantityCellClass = stock < quantity ? 'background-color: #fff8c4; color: #7a6600;' : '';






      // ── MODIFIED: TOD eligibility gate ────────────────────────────
      // isTodEligible is injected by Apex (createInvoiceData).
      // Default true for any line that arrives without the flag (safety).
      const todEligible = element.isTodEligible !== false;



      if (!element.isPromotional && !todEligible) {
        // MRP per piece <= 20 → force TOD to zero for this non-promo line
        element.discount1Amt = 0;
      } else {
        // TOD eligible (or promotional): use persisted Discount_1__c
        element.discount1Amt = element.Discount_1__c || 0;
      }

      // Persist the flag so other methods (dis2PercentHandler,
      // handleLineItemSave) can re-use it without re-fetching.
      element.isTodEligible = todEligible;
      // ── END MODIFIED block ────────────────────────────────────────

      element.discount2Amt = element.Discount_2__c || 0;

      // Purchase Quantity Discount scheme amount for this line. Computed fresh from the
      // (undiscounted) Price__c and the scheme's stored %, same shape as TOD's calc
      // above, unless it's already been persisted (Scheme_Discount_Amount__c).
      const schemeInfo = element.Quantity_Scheme_Applied__r;
      if (!element.isPromotional && element.Quantity_Scheme_Applied__c
          && schemeInfo && schemeInfo.Type__c === 'Purchase Quantity Discount') {
        const schemePercent = Number(schemeInfo.Discount_Percentage__c) || 0;
        element.schemeDiscountAmt = (element.Quantity__c * element.Price__c * schemePercent / 100).toFixed(2);
      } else {
        element.schemeDiscountAmt = element.Scheme_Discount_Amount__c || 0;
      }

      totalDis1 += element.discount1Amt || 0;
      totalDis2 += element.discount2Amt || 0;
      totalDis3 += Number(element.schemeDiscountAmt) || 0;

      if (Object.hasOwn(element, 'Product__r')) {

        element.ProductName = element.Product__r.Name;
      }
      if (element.isPromotional && element.ProductName && !element.ProductName.startsWith('🎁')) {
        element.ProductName = `🎁 ${element.ProductName}`;
      }

      this.itemList.forEach((promo) => {
        if (promo.isPromotional && promo.parentProductId && promo.selectedSchemeId) {
          const baseRow = this.itemList.find(
            (r) => !r.isPromotional && r.Product__c === promo.parentProductId
          );
          if (baseRow) {
            baseRow.selectedSchemeId = promo.selectedSchemeId;
          }
        }
      });
    });

    this.itemList = [...this.itemList];
    this.itemList = this.recalculatePromoLocks(this.itemList);
    this.totalDisPercent = this.invoiceInfo.Discount_1__c;
    this.totalDiscount1 = totalDis1;
    this.totalDiscount2 = totalDis2;
    this.totalSchemeDiscount = Math.round(totalDis3 * 100) / 100;
    this.totalDiscount = Math.round((totalDis1 + totalDis2 + totalDis3) * 100) / 100;
    this.originalItemList = [...this.itemList];

    if (!isNullEmptyUndefined(this.invoiceInfo.Id)) {
      this.readMode = true;

    }

    // Now that itemList is populated, re-resolve the applied Value Scheme's real discount
    // against the live cart lines — see the note above where this used to be called too
    // early. This corrects any stale/pre-fix rupee amount that may still be persisted on
    // the Invoice record.
    if (this.ValueSchemeExist) {
      this.restoreValueSchemeThreshold();
    }

    this.handlePriceCalculations();
  }

  formatDateForDisplay(dateStr) {
    if (!dateStr) return '';
    // Append T00:00:00 to avoid UTC offset shifting the date
    return new Date(dateStr + 'T00:00:00').toLocaleDateString('en-IN', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
  }

  getTodayDateString() {
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const yyyy = today.getFullYear();
    const mm = String(today.getMonth() + 1).padStart(2, '0');
    const dd = String(today.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  invoiceDateHandler(event) {

    const selectedDate = event.target.value;


    if (!selectedDate) return;

    const todayStr = this.getTodayDateString();
    const earliestStr = this.getEarliestAllowedDate();

    if (selectedDate > todayStr) {
      this.dispatchEvent(showToast('Error', 'Invoice Date cannot be in the future.', [], 'error', 'sticky'));
      event.target.value = this.invoiceInfo.Invoice_Date__c;
      return;
    }

    if (selectedDate < earliestStr) {
      const isOrderDateBinding = this.lastValidInvoiceDate && earliestStr === this.lastValidInvoiceDate;
      const message = isOrderDateBinding ?
      `Invoice Date cannot be before the Order Date (${this.formatDateForDisplay(this.lastValidInvoiceDate)}).` :
      `Invoice Date cannot be more than 3 days in the past. Earliest allowed date is ${this.formatDateForDisplay(earliestStr)}.`;
      this.dispatchEvent(showToast('Error', message, [], 'error', 'sticky'));
      event.target.value = this.invoiceInfo.Invoice_Date__c;
      return;
    }

    this.invoiceInfo.Invoice_Date__c = selectedDate;

  }

  // Returns YYYY-MM-DD that is N calendar days before the given YYYY-MM-DD string
  getDateMinusCalendarDays(dateStr, days) {
    const [y, m, d] = dateStr.split('-').map(Number);
    const date = new Date(y, m - 1, d);
    date.setDate(date.getDate() - days);
    const yyyy = date.getFullYear();
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    return `${yyyy}-${mm}-${dd}`;
  }

  // Returns the earliest selectable invoice date (later of: today-3 days OR order date)
  getEarliestAllowedDate() {
    const todayStr = this.getTodayDateString();
    const minFromToday = this.getDateMinusCalendarDays(todayStr, 3);
    const minFromOrder = this.lastValidInvoiceDate || minFromToday;

    // Take whichever lower bound is later (more restrictive)
    return minFromOrder > minFromToday ? minFromOrder : minFromToday;
  }

  get minInvoiceDate() {
    return this.getEarliestAllowedDate();
  }

  get maxInvoiceDate() {
    return this.getTodayDateString();
  }

  creditPeriodHandler(event) {

    this.invoiceInfo.Credit_Period__c = event.target.value;

  }

  dis2PercentHandler(event) {
    const inputCmp = event.target;
    let dis2 = inputCmp.value;


    if (dis2 === '') dis2 = 0;
    dis2 = parseFloat(dis2);

    if (isNaN(dis2) || dis2 !== 0 && (dis2 < 1 || dis2 > 100)) {
      this.invoiceInfo.Discount_2__c = ' ';
      dis2 = ' ';
      inputCmp.setCustomValidity("Please enter a Discount 2% between 1 and 100.");
      inputCmp.reportValidity();
      this.dispatchEvent(showToast('Warning!', 'Please enter a Discount 2% between 1 and 100.', [], 'error', ''));
    } else {
      inputCmp.setCustomValidity("");
      inputCmp.reportValidity();
      this.invoiceInfo.Discount_2__c = dis2;
    }

    let totalDis1 = 0;
    let totalDis2 = 0;
    let totalDis3 = 0;

    this.itemList.forEach((element) => {
      const qty = parseFloat(element.Quantity__c || 0);
      const price = parseFloat(element.Price__c || 0);

      // Discount 2 applies to all items regardless of TOD eligibility
      const dis2Amt = qty * price * dis2 / 100;
      element.discount2Amt = Math.round(dis2Amt * 100) / 100;

      // ── MODIFIED: re-enforce TOD eligibility on dis1 ─────────────
      // isTodEligible was stored on the element during constructInvoiceData
      // or handleLineItemSave; default true for safety/backward-compat.
      const todEligible = element.isTodEligible !== false;
      if (!element.isPromotional && !todEligible) {
        // MRP per piece <= 20 → keep discount1Amt at 0
        element.discount1Amt = 0;
      }
      // If todEligible, discount1Amt was already computed and stored on
      // the element — we do not change it here; only dis2 changed.
      // ── END MODIFIED block ────────────────────────────────────────

      element.totalDiscountAmt = Math.round(((element.discount1Amt || 0) + element.discount2Amt) * 100) / 100;
      totalDis1 += element.discount1Amt || 0;
      totalDis2 += element.discount2Amt || 0;
      // Scheme discount doesn't change when Discount 2% changes — carry forward the
      // value already computed in constructInvoiceData / handleLineItemSave.
      totalDis3 += Number(element.schemeDiscountAmt) || 0;
    });

    this.totalDisPercent = ((parseFloat(this.invoiceInfo.Discount_1__c) || 0) + (parseFloat(dis2) || 0)).toFixed(2);
    this.totalDiscount1 = Math.round(totalDis1 * 100) / 100;
    this.totalDiscount2 = Math.round(totalDis2 * 100) / 100;
    this.totalSchemeDiscount = Math.round(totalDis3 * 100) / 100;
    this.totalDiscount = Math.round((totalDis1 + totalDis2 + totalDis3) * 100) / 100;

    this.itemList = [...this.itemList];
    this.handlePriceCalculations();
  }

  handleRowAction(event) {


    const actionname = event.detail.action.name;

    const row = event.detail.row;
    switch (actionname) {
      case 'edit':

        this.showModal = true;
        this.rowIndex = row.rowNo;
        this.rowAction = 'edit';
        this.iliProduct = row.Product__c;
        this.iliQuantity = row.Quantity__c;
        this.iliPrice = row.Price__c;
        this.iliStockInHand = row.CurrentStock;
        this.iliEdit = true;
        this.searchQuery = row.ProductName || '';
        this.selectedProduct = { Id: row.Product__c, Name: row.ProductName, Stock: row.CurrentStock };
        this.iliSkuDiscountPercent = row.SKU_Discount_Percent__c || 0;
        break;
      case 'add':

        this.showModal = true;
        this.rowIndex = row.rowNo;
        this.iliEdit = false;
        this.iliProduct = '';
        this.iliQuantity = '';
        this.iliPrice = '';
        this.iliStockInHand = '';
        this.rowAction = 'add';
        this.searchQuery = '';
        this.selectedProduct = null;
        this.searchBy = 'Name';
        this.searchByDisplayText = 'Name';
        this.showSearchByDropdown = false;
        if (this.handleClickOutside) {
          document.removeEventListener('click', this.handleClickOutside);
        }
        this.iliSkuDiscountPercent = 0;
        break;
      case 'delete':

        let tempData = [...this.itemList];
        if (tempData.length == 1) {
          this.dispatchEvent(showToast('Important!', 'There should be atleast one line item present, use Edit option to modify.', [], 'info', ''));
          return;
        }
        const itemToDelete = tempData.find((ele) => ele.rowNo === row.rowNo);
        const itemId = itemToDelete?.Id;
        if (itemId) {
          this.deletedItemIds.push(itemId);

        }
        if (itemToDelete?.isPromotional && itemToDelete?.promoType === 'VALUE') {
          this.clearValueScheme();
        }
        if (itemToDelete?.isPromotional && !itemToDelete?.promoType) {
          const parentId = itemToDelete.parentProductId;
          tempData.forEach((r) => {
            if (!r.isPromotional && r.Product__c === parentId) r.selectedSchemeId = null;
          });
        }
        tempData = tempData.filter((ele) => ele.rowNo !== row.rowNo);
        tempData = this.recalculatePromoLocks(tempData);
        tempData.forEach((element, index) => element.rowNo = index + 1);
        this.itemList = [...tempData];
        this.recalculateDiscountTotals();
        this.handlePriceCalculations();
        this.applyStockValidationUI();
        this.removeInvalidValueSchemeFromInvoice();
        break;
      case 'scheme':
        this.openQuantitySchemeFromInvoice(row);
        break;
    }
  }

  recalculateDiscountTotals() {
    let totalDis1 = 0;
    let totalDis2 = 0;
    let totalDis3 = 0;
    this.itemList.forEach((item) => {
      totalDis1 += item.discount1Amt || 0;
      totalDis2 += item.discount2Amt || 0;
      totalDis3 += Number(item.schemeDiscountAmt) || 0;
    });
    this.totalDiscount1 = Math.round(totalDis1 * 100) / 100;
    this.totalDiscount2 = Math.round(totalDis2 * 100) / 100;
    this.totalSchemeDiscount = Math.round(totalDis3 * 100) / 100;
    this.totalDiscount = Math.round((totalDis1 + totalDis2 + totalDis3) * 100) / 100;
  }

  handleSearchChange(event) {
    this.searchQuery = event.target.value;
    window.clearTimeout(this.searchDebounce);
    if (!this.searchQuery || this.searchQuery.length < 2) {
      this.productResults = [];
      this.showDropdown = false;
      return;
    }
    this.searchDebounce = window.setTimeout(() => {
      this.performProductSearch(this.searchQuery);
    }, this.searchDebounceTime);
  }

  handleSearchFocus() {
    if (this.productResults && this.productResults.length > 0) this.showDropdown = true;
  }

  handleSearchByOptionSelect(event) {
    const selected = event.currentTarget.dataset.searchby;
    this.searchBy = selected;
    this.searchByDisplayText = selected;
    this.showSearchByDropdown = false;
    if (this.handleClickOutside) document.removeEventListener('click', this.handleClickOutside);
    if (this.searchQuery && this.searchQuery.length >= 2) this.performProductSearch(this.searchQuery);
  }

  toggleSearchByDropdown() {
    this.showSearchByDropdown = !this.showSearchByDropdown;
    if (this.showSearchByDropdown) {
      setTimeout(() => {
        this.handleClickOutside = this.handleClickOutside.bind(this);
        document.addEventListener('click', this.handleClickOutside);
      }, 0);
    } else {
      if (this.handleClickOutside) document.removeEventListener('click', this.handleClickOutside);
    }
  }

  handleClickOutside(event) {
    const dropdownContainer = this.template.querySelector('[data-searchby-container]');
    if (dropdownContainer && !dropdownContainer.contains(event.target)) {
      this.showSearchByDropdown = false;
      if (this.handleClickOutside) document.removeEventListener('click', this.handleClickOutside);
    }
  }

  performProductSearch(searchKey) {
    this.isLoading = true;
    getProductsWithStock({ searchKey: searchKey, searchBy: this.searchBy }).
    then((result) => {
      this.productResults = (result || []).map((r) => ({ Id: r.Id, Name: r.Name, Stock: r.Stock }));
      this.showDropdown = this.productResults.length > 0;
    }).
    catch((err) => {

      this.productResults = [];
      this.showDropdown = false;
    }).
    finally(() => {this.isLoading = false;});
  }

  handleSelectProduct(event) {
    const pid = event.currentTarget.dataset.id;
    const sel = this.productResults.find((p) => p.Id === pid);
    if (!sel) return;
    this.selectedProduct = sel;
    this.searchQuery = sel.Name;
    this.showDropdown = false;
    this.iliProduct = sel.Id;

    this.iliStockInHand = sel.Stock || 0;
    this.fetchPriceAndStock(sel.Id);
  }

  async fetchPriceAndStock(productId) {
    try {
      if (this.isCounterFlow) {
        // Counter Invoice: price depends on the Price Type (MRP/Dealer Price)
        // picked back in Step 1, not on retailer state/type at all.
        const result = await getPriceForProduct({ productId, priceType: this.priceType });
        this.iliPrice = result.price ? parseFloat(result.price).toFixed(2) : 0;
        return;
      }
      const state = this.retailerInfo.Primary_State__c;
      const type = this.retailerInfo.Distributor_Type__c ?? 'Retailer';
      const result = await getPriceByProduct({ productId, state, accountType: type });
      this.iliPrice = result.price ? parseFloat(result.price).toFixed(2) : 0;
      this.iliStockInHand = result.stockInHand != null ? parseFloat(result.stockInHand) : this.iliStockInHand || 0;
      await getMRPByProduct({ productId });
    } catch (err) {
    }
  }

  clearProductSelection() {
    this.selectedProduct = null;
    this.searchQuery = '';
    this.productResults = [];
    this.showDropdown = false;
    this.iliProduct = undefined;
    this.iliStockInHand = undefined;
    this.iliPrice = undefined;
  }

  async handleProductChange(event) {


    const productId = this.iliProduct;

    const state = this.retailerInfo.Primary_State__c;
    const type = this.retailerInfo.Distributor_Type__c ?? 'Retailer';
    if (!productId) return;
    try {
      const result = await getPriceByProduct({ productId, state, accountType: type });
      this.iliPrice = result.price ? parseFloat(result.price).toFixed(2) : 0;
      this.iliStockInHand = result.stockInHand ? parseFloat(result.stockInHand) : 0;
    } catch (error) {
      this.dispatchEvent(showToast('Error', 'Error fetching price or stock for selected product', [], 'error', ''));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MODIFIED: handleLineItemSave
  //
  // Changes:
  //  1. Read result.isTodEligible from the updated ProductWrapper returned by
  //     getProductName().  If false → discount1 = 0, newdiscount1 = 0.
  //  2. Persist isTodEligible on the newly created / edited item object so
  //     dis2PercentHandler and other recalculation methods can re-use it
  //     without re-fetching.
  //
  // All other logic in this method is unchanged.
  // ─────────────────────────────────────────────────────────────────────────
  async handleLineItemSave() {
    if (this.isProductSaving) return;
    this.isProductSaving = true;

    const ili_product = this.iliProduct;
    const ili_quantity_raw = this.template.querySelector('lightning-input-field[data-id=ili_quantity]').value;
    const ili_price_raw = this.iliPrice;

    const ili_quantity = parseInt(ili_quantity_raw);
    const ili_price = parseFloat(ili_price_raw);

    if (isNullEmptyUndefined(ili_product) || isNullEmptyUndefined(ili_quantity) || isNullEmptyUndefined(ili_price)) {
      this.dispatchEvent(showToast('Error', 'Fill all the field information to proceed with Save', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }
    if (parseFloat(ili_price) <= 0) {
      this.dispatchEvent(showToast('Error', 'Price should be greater than 0', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }
    if (ili_quantity <= 0) {
      this.dispatchEvent(showToast('Error', 'Quantity should be greater than 0', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }

    let productName = "";
    let productMRP = 0;
    let stockQuantity = 0;
    let productLevelDiscount = 0;
    // ── NEW: TOD eligibility flag returned by updated ProductWrapper ──
    let todEligible = true; // default true; overwritten by Apex response
    let success = false;

    try {



      const result = await getProductName({
        productId: ili_product,
        accountId: this.invoiceInfo?.Retailer_Account__c || this.invoiceInfo?.Under_SS__c
      });

      if (!isNullEmptyUndefined(result)) {

        productName = result.name;
        productLevelDiscount = result.discount ?? 0;
        // ── MODIFIED: read isTodEligible from ProductWrapper ──────
        todEligible = result.isTodEligible !== false; // default true if absent

        success = true;
      }

      const [mrpResult, stockResult] = await Promise.all([
      getMRPByProduct({ productId: ili_product }),
      getStockByProducts({ productIds: [ili_product] })]
      );
      if (mrpResult) productMRP = mrpResult;
      if (stockResult && stockResult[ili_product]) stockQuantity = stockResult[ili_product];

    } catch (error) {
      this.dispatchEvent(showToast('Error', 'Error while fetching product information', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }

    // ── MODIFIED: compute discount1 with TOD eligibility gate ────────
    // productLevelDiscount is already 0 when !todEligible (Apex ensures
    // this), but we guard here too for defence-in-depth.
    let discount1 = todEligible ?
    productLevelDiscount > 0 ? productLevelDiscount : this.invoiceInfo.Discount_1__c ?? 0 :
    0;
    // ── END MODIFIED block ────────────────────────────────────────────

    const discount2 = this.invoiceInfo.Discount_2__c ?? 0;
    // SKU-wise discount % from the modal (percentage only)
    const skuDiscRaw = this.template.querySelector('lightning-input[data-id=ili_sku_discount]')?.value;
    const skuDisc = skuDiscRaw ? parseFloat(skuDiscRaw) : 0;
    if (isNaN(skuDisc) || skuDisc < 0 || skuDisc > 100) {
      this.dispatchEvent(showToast('Error', 'SKU Discount % must be between 0 and 100', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }
    if (skuDisc > 0 && Number(this.invoiceInfo.Discount_2__c) > 0) {
      this.dispatchEvent(showToast('Error', 'Overall Discount 2 and SKU-wise Discount cannot be used together. Clear Overall Discount 2 first.', [], 'error', ''));
      this.isProductSaving = false;
      return;
    }
    const newdiscount1 = todEligible ? Math.round(ili_price * ili_quantity * (discount1 / 100) * 100) / 100 : 0;
    // SKU-wise wins for this line; otherwise fall back to the overall %
    const newdiscount2 = skuDisc > 0
      ? Math.round(ili_price * ili_quantity * (skuDisc / 100) * 100) / 100
      : Math.round(ili_price * ili_quantity * (discount2 / 100) * 100) / 100;
    const quantityCellClass = stockQuantity < ili_quantity ? 'background-color: #fff8c4; color: #7a6600;' : '';

    if (success) {
      if (this.rowAction === 'add') {
        const duplicateItem = this.itemList.find((item) => item.Product__c === ili_product);
        if (duplicateItem) {
          const duplicateLineNumber = duplicateItem.rowNo || this.itemList.indexOf(duplicateItem) + 1;
          this.dispatchEvent(showToast(
            'Error',
            `You've already added ${productName} in line #${duplicateLineNumber}. To make changes, please edit that line item.`,
            [], 'error', ''
          ));
          this.isProductSaving = false;
          return;
        }

        const newItem = {
          "Price__c": ili_price,
          "Product__c": ili_product,
          "Quantity__c": ili_quantity,
          "Total_Amount__c": +(ili_price * ili_quantity).toFixed(2),
          "rowNo": this.rowIndex,
          "hsn": INVOICE_HSN_LABEL,
          "mrp": productMRP,
          "ProductName": productName,
          "CurrentStock": stockQuantity,
          "discount1Amt": newdiscount1,
          "discount2Amt": newdiscount2,
          "SKU_Discount_Percent__c": skuDisc,
          "Discount_Percentage__c": todEligible ? productLevelDiscount : 0,
          "quantityCellClass": quantityCellClass,
          // ── NEW: persist eligibility flag ──────────────────────
          "isTodEligible": todEligible
        };
        this.itemList.splice(this.rowIndex, 0, newItem);
        this.itemList.forEach((element, index) => element.rowNo = index + 1);
        this.itemList = [...this.itemList];
      } else
      if (this.rowAction === 'edit') {
        this.itemList.forEach((element, index) => {
          if (this.rowIndex === index + 1) {
            element.Price__c = ili_price;
            element.Product__c = ili_product;
            element.Quantity__c = ili_quantity;
            element.Total_Amount__c = +(ili_price * ili_quantity).toFixed(2);
            element.ProductName = productName;
            element.discount1Amt = newdiscount1;
            element.discount2Amt = newdiscount2;
            element.SKU_Discount_Percent__c = skuDisc;
            element.Discount_Percentage__c = todEligible ? productLevelDiscount : 0;
            element.quantityCellClass = quantityCellClass;
            // ── NEW: update eligibility flag on edited row ─────
            element.isTodEligible = todEligible;
          }
        });
        this.itemList = [...this.itemList];
      }

      this.recalculateDiscountTotals();
      this.selectedProduct = null;
      this.iliProduct = undefined;
      this.iliQuantity = undefined;
      this.iliPrice = undefined;
      this.iliStockInHand = undefined;
      this.showModal = false;
      this.handlePriceCalculations();
      const editedProductId = ili_product;
      this.removeInvalidPromosFromInvoice(editedProductId);
      this.reapplyQuantitySchemeFromInvoice(editedProductId);
      this.applyStockValidationUI();
    }

    this.isProductSaving = false;
  }

  handleLineItemCancel() {
    this.searchBy = 'Name';
    this.searchByDisplayText = 'Name';
    this.showSearchByDropdown = false;
    if (this.handleClickOutside) document.removeEventListener('click', this.handleClickOutside);
    this.showModal = false;
  }

  handlePriceCalculations() {
    let data = [...this.itemList];

    let totalQuantity = 0;
    let taxableValue = 0;
    let totalGST = 0;
    let invoiceAmount = 0;
    let sgstAmount = 0;
    let cgstAmount = 0;
    let igstAmount = 0;
    let grossCartTotal = 0;

    if (
    this.ValueSchemeExist &&
    !this.discountAmountGivenCheck &&
    !this.discountPercemtageGivenCheck &&
    Number(this.invoiceInfo.Value_Scheme_Discount__c) > 0)
    {
      this.discountAmountGiven = Number(this.invoiceInfo.Value_Scheme_Discount__c);
      this.discountAmountGivenCheck = true;
    }

    // Legal requirement: MRP is tax-inclusive under Indian Legal Metrology rules — the
    // displayed MRP already contains GST. Per Finance's clarification, GST must still be
    // calculated/shown (for GST return filing) but EXTRACTED from within the MRP rather
    // than zeroed out or added on top — see the taxableValue extraction below.
    // Per explicit business decision this applies ONLY to the Counter Invoice flow —
    // regular Secondary Orders must always be taxed normally (added on top) regardless of
    // Price_Type__c, so this is gated on isCounterFlow as well (this component is shared
    // by both edit flows, isCounterFlow is set at line ~178 from Order__r.Type__c ===
    // 'Counter Order'). The percentages themselves are NOT zeroed — same normal rate as
    // Dealer Price.
    const isMrp = this.isCounterFlow && this.priceType === 'MRP';
    let sgstPercent = this.invoiceInfo.SGST__c && Number(this.invoiceInfo.SGST__c) ? this.invoiceInfo.SGST__c : 0;
    let cgstPercent = this.invoiceInfo.CGST__c && Number(this.invoiceInfo.CGST__c) ? this.invoiceInfo.CGST__c : 0;
    let igstPercent = !sgstPercent && !cgstPercent && this.invoiceInfo.IGST__c && Number(this.invoiceInfo.IGST__c) ? this.invoiceInfo.IGST__c : 0;

    // Per-line display values (Rate/Amount columns). Counter Invoice + MRP only: show the
    // tax-EXCLUDED Rate/Amount so Basic Amount and Taxable Amount line up. Display-only —
    // the real Price__c/Total_Amount__c saved to Invoice_Line_Item__c are untouched.
    const lineTotalRatePercent = sgstPercent + cgstPercent + igstPercent;
    data.forEach((item) => {
      if (!isNullEmptyUndefined(item.Quantity__c))
      totalQuantity = totalQuantity + parseInt(item.Quantity__c);
      if (!isNullEmptyUndefined(item.Total_Amount__c))
      taxableValue = taxableValue + parseFloat(item.Total_Amount__c);
      if (!isNullEmptyUndefined(item.Total_Amount__c))
      grossCartTotal += parseFloat(item.Total_Amount__c);

      const rawAmount = !isNullEmptyUndefined(item.Total_Amount__c) ? parseFloat(item.Total_Amount__c) : 0;
      const rawQty = !isNullEmptyUndefined(item.Quantity__c) ? parseFloat(item.Quantity__c) : 0;
      if (isMrp && lineTotalRatePercent > 0) {
        const extractedAmount = rawAmount / (1 + lineTotalRatePercent / 100);
        item.displayTotalAmount__c = this.roundNum(extractedAmount);
        item.displayPrice__c = rawQty > 0 ? this.roundNum(extractedAmount / rawQty) : item.Price__c;
        // Discount 2 must be extracted by the SAME factor as Amount/Rate above, so that
        // displayTotalAmount__c - displayDiscount2Amt reconstructs to the true taxable
        // value for this line. discount2Amt itself (raw) is left untouched since it's
        // what actually gets saved to Discount_2__c.
        item.displayDiscount2Amt = this.roundNum((Number(item.discount2Amt) || 0) / (1 + lineTotalRatePercent / 100));
      } else {
        item.displayTotalAmount__c = item.Total_Amount__c;
        item.displayPrice__c = item.Price__c;
        item.displayDiscount2Amt = item.discount2Amt;
      }

      // Purchase Quantity Discount: Total_Amount__c/Price__c intentionally stay at the
      // FULL (undiscounted) price server-side (see SecondaryInvoiceHandler.
      // createNewInvoiceItems()) — Taxable Value is reduced by this same schemeDiscountAmt
      // separately via totalDis3 (this.totalDiscount), so Total_Amount__c must stay gross
      // or the discount would be double-counted there. The DISPLAYED Amount/Rate columns,
      // though, should show the discount already netted in — matching what the Order page
      // shows for the same line. Mirrors secondaryInvoice.js's fix (decision log §8.10).
      const qtySchemeType = item.Quantity_Scheme_Applied__r?.Type__c || item.schemeType;
      if (!item.isPromotional && qtySchemeType === 'Purchase Quantity Discount' && Number(item.schemeDiscountAmt) > 0) {
        const schemeDiscount = Number(item.schemeDiscountAmt) || 0;
        item.displayTotalAmount__c = this.roundNum((Number(item.displayTotalAmount__c) || 0) - schemeDiscount);
        item.displayPrice__c = rawQty > 0 ? this.roundNum(item.displayTotalAmount__c / rawQty) : item.displayPrice__c;
      }
    });

    const cartTotalBeforeValueScheme = this.roundNum(grossCartTotal - this.totalDiscount);
    this.grossCartTotal = cartTotalBeforeValueScheme;

    // RE-EVALUATE VALUE SCHEME against the CURRENT cart total on every calculation pass —
    // not just once the cart drops below the threshold it was originally applied at. Flat
    // Discount schemes are tiered (Scheme_Slab__c), so any change to the cart total can
    // change which slab applies, or remove eligibility entirely. Mirrors
    // secondaryInvoice.js's reapplyValueSchemeOnInvoice() (decision log §8.5/§8.13) —
    // replaces the old below-minimum-only removal block, which never re-resolved to a
    // different still-valid slab.
    this.reapplyValueSchemeOnInvoice();

    if (this.discountAmountGivenCheck) taxableValue = taxableValue - this.discountAmountGiven;
    if (this.discountPercemtageGivenCheck) {
      // Scoped Flat Discount schemes must discount only the matched SKUs' subtotal
      // (valueSchemeQualifyingSubtotal), not the whole cart's taxableValue — otherwise the
      // % leaks onto non-matching SKUs. Falls back to taxableValue for global schemes (no
      // Scheme_Applicability__c rows). See decision log §8.6/§8.13.
      const pctBase = this.valueSchemeQualifyingSubtotal != null ?
        this.valueSchemeQualifyingSubtotal : taxableValue;
      taxableValue = taxableValue - pctBase * this.discountPercemtageGiven / 100;
    }



    taxableValue = taxableValue - this.totalDiscount;

    // MRP extraction (Counter Invoice + MRP only): back the taxable value out of the
    // tax-inclusive amount so that taxableValue + GST reconstructs to the original
    // MRP-based amount instead of adding GST on top of it.
    const totalRatePercent = sgstPercent + cgstPercent + igstPercent;
    if (isMrp && totalRatePercent > 0) {
      taxableValue = taxableValue / (1 + totalRatePercent / 100);
    }

    // ── Multi-Scheme Retailer Reimbursement — applied AFTER other discounts,
    //    one scheme at a time, each capped at its own remaining balance
    //    against whatever taxable value is left after the previous scheme.
    sgstAmount = taxableValue * sgstPercent / 100;
    cgstAmount = taxableValue * cgstPercent / 100;
    igstAmount = taxableValue * igstPercent / 100;
    totalGST = (Number(sgstAmount) ? sgstAmount : 0) + (Number(cgstAmount) ? cgstAmount : 0) + (Number(igstAmount) ? igstAmount : 0);


    this.invoiceInfo.Total_Quantity__c = totalQuantity;
    this.invoiceInfo.Taxable_Amount__c = this.roundNum(taxableValue);
    this.invoiceInfo.SGST_Amount__c = this.roundNum(sgstAmount);
    this.invoiceInfo.CGST_Amount__c = this.roundNum(cgstAmount);
    this.invoiceInfo.IGST_Amount__c = this.roundNum(igstAmount);
    this.invoiceInfo.Total_GST__c = this.roundNum(totalGST);

    let taxablePlusGST = this.invoiceInfo.Taxable_Amount__c + this.invoiceInfo.Total_GST__c;
    let totalInvoiceAmountRounded = Math.round(taxablePlusGST);
    this.roundOff = this.roundNum(totalInvoiceAmountRounded - taxablePlusGST);
    invoiceAmount = totalInvoiceAmountRounded;
    this.invoiceInfo.Invoice_Amount__c = totalInvoiceAmountRounded;

    // ── Multi-Scheme Retailer Reimbursement — display-only figure.
    //    Taxable_Amount__c, GST fields, and Invoice_Amount__c above
    //    (the true, legally-invoiced Net Amount) are never touched
    //    by this. This only produces netPayable — what the retailer
    //    actually owes after reimbursement — for display purposes.
    let netPayable = this.invoiceInfo.Invoice_Amount__c;
    if (this.activeSchemes && this.activeSchemes.length > 0) {
      this.activeSchemes = this.activeSchemes.map((s) => {
        if (!s.isApplied) {
          return { ...s, amountApplied: 0 };
        }
        let amt = Math.min(s.balance, netPayable);
        if (amt < 0) amt = 0;
        netPayable -= amt;
        return { ...s, amountApplied: this.roundNum(amt) };
      });
    }
    this.netPayable = this.roundNum(netPayable);



this.invoiceInfo.Invoice_Amount_In_Words__c = this.amountToWords(this.invoiceInfo.Invoice_Amount__c);

    if (this.ValueSchemeExist) {
      if (this.discountAmountGivenCheck) {
        this.invoiceInfo.Value_Scheme_Discount__c = Number(this.discountAmountGiven) || 0;
      } else if (this.discountPercemtageGivenCheck) {
        const pctBase = this.valueSchemeQualifyingSubtotal != null ?
          this.valueSchemeQualifyingSubtotal : this.grossCartTotal;
        // For MRP invoices, pctBase (and taxableValue/grossCartTotal at the point the REAL
        // discount math runs, above) are still tax-INCLUSIVE — the MRP extraction division
        // only happens later, after the discount is already netted into taxableValue, so
        // the real Taxable Value ends up correct automatically. This persisted/displayed
        // figure is computed independently and must apply the same extraction explicitly
        // here, or it shows the bigger tax-inclusive discount amount instead of the pre-tax
        // figure actually reflected in Taxable Value. Kept at 2 decimal places (roundNum),
        // not rounded to a whole rupee. Mirrors secondaryInvoice.js §8.9/§8.11.
        const displayPctBase = isMrp && lineTotalRatePercent > 0 ?
          pctBase / (1 + lineTotalRatePercent / 100) : pctBase;
        this.invoiceInfo.Value_Scheme_Discount__c =
          this.roundNum(displayPctBase * this.discountPercemtageGiven / 100);
      }
    } else {
      this.invoiceInfo.Value_Scheme_Discount__c = 0;
    }











    this.applyStockValidationUI();
    this.refreshFreeOfferMessage();
  }

  // Modern Trade free-goods scheme — recomputed any time the cart/line items change so it
  // always reflects the current summed quantity of qualifying products.
  refreshFreeOfferMessage() {
    const productQty = (this.itemList || [])
      .filter((i) => i.Product__c)
      .map((i) => ({ productId: i.Product__c, quantity: parseFloat(i.Quantity__c) || 0 }));

    if (productQty.length === 0) {
      this.freeOfferMessage = null;
      return;
    }

    getFreeOfferMessageForProducts({ productQtyJson: JSON.stringify(productQty) })
      .then((message) => { this.freeOfferMessage = message || null; })
      .catch((error) => {
        this.freeOfferMessage = null;
        // Temporary diagnostic: this call was previously failing silently with no
        // visibility into why. Surface the real error so it can be diagnosed, then
        // this can be reverted back to a quiet catch once resolved.
        // eslint-disable-next-line no-console
        console.error('getFreeOfferMessageForProducts failed:', JSON.stringify(error));
        this.dispatchEvent(showToast(
          'Error',
          'Free offer check failed: ' + (error?.body?.message || error?.message || JSON.stringify(error)),
          [], 'error', 'sticky'
        ));
      });
  }

  roundNum(num) {return Math.round((num + Number.EPSILON) * 100) / 100;}

  // ── Multi-Scheme Retailer Reimbursement handlers ───────────────────────
  openReimbursementDialog() {
    this.isReimbursementDialog = true;
  }

  closeReimbursementDialog() {
    this.isReimbursementDialog = false;
  }

  toggleActiveScheme(event) {
    const id = event.target.dataset.id;
    this.activeSchemes = this.activeSchemes.map((s) =>
      s.allocationId === id ? { ...s, isApplied: !s.isApplied } : s
    );
    this.handlePriceCalculations();
  }

  // Purchase Quantity Discount schemes no longer touch Price__c (Rate stays at the
  // full list price) — the discount is captured separately per line in
  // schemeDiscountAmt / Scheme_Discount_Amount__c. This groups those amounts by
  // scheme Id for display just above Taxable Value.
  get appliedQuantityDiscountSchemes() {
    const schemeMap = new Map();
    (this.itemList || []).forEach((item) => {
      const schemeInfo = item.Quantity_Scheme_Applied__r;
      if (item.Is_Promotional__c || !item.Quantity_Scheme_Applied__c || !schemeInfo) return;
      if (schemeInfo.Type__c !== 'Purchase Quantity Discount') return;

      const discountPercent = Number(schemeInfo.Discount_Percentage__c) || 0;
      const savedTotal = Number(item.schemeDiscountAmt) || 0;
      if (savedTotal <= 0) return;

      const key = item.Quantity_Scheme_Applied__c;
      const existing = schemeMap.get(key);
      if (existing) {
        existing.discountAmount = this.roundNum(Number(existing.discountAmount) + savedTotal);
      } else {
        schemeMap.set(key, {
          schemeId: key,
          schemeName: schemeInfo.Name,
          discountPercent,
          discountAmount: this.roundNum(savedTotal)
        });
      }
    });
    return Array.from(schemeMap.values());
  }

 get appliedSchemeCount() {
    return this.activeSchemes.filter((s) => s.isApplied).length;
  }
 get appliedSchemesList() {
    return (this.activeSchemes || []).filter((s) => s.isApplied && s.amountApplied > 0);
  }
  get amountInWordsRowspan() {
    // Fixed rows always present: Total Unit, Discount 2, Discount Total,
    // Taxable Value, Total GST, Round Off, Invoice Value = 7
    // Plus exactly one row per applied scheme, plus 1 more for Net Payable
    // only when at least one scheme is actually showing.
    const baseRows = 7;
    const schemeRows = this.appliedSchemesList.length;
    const netPayableRow = schemeRows > 0 ? 1 : 0;
    return baseRows + schemeRows + netPayableRow;
  }

  remarksHandler(event) {
    this.invoiceInfo.Remarks__c = event.target.value;
  }
  roundNumber(num) {return Math.round(num);}

  amountToWords(amount) {
    if (amount < 0) return '';
    if (amount == 0) return 'Zero';
    const units = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
    'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'];
    const tens = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];
    function convert(num) {
      if (num < 20) return units[Math.trunc(num)] + ' ';
      if (num < 100) return tens[Math.trunc(num / 10)] + (num % 10 > 0 ? ' ' + convert(num % 10) : ' ');
      if (num < 1000) return units[Math.trunc(num / 100)] + ' Hundred and' + (num % 100 > 0 ? ' ' + convert(num % 100) : '');
      if (num < 10000) return units[Math.trunc(num / 1000)] + ' Thousand ' + (num % 1000 > 0 ? ' ' + convert(num % 1000) : '');
      if (num < 100000) return convert(num / 1000) + ' Thousand ' + (num % 1000 > 0 ? '' + convert(num % 1000) : '');
      if (num < 1000000) return units[Math.trunc(num / 100000)] + ' Lakh ' + (num % 100000 > 0 ? '' + convert(num % 100000) : '');
      if (num < 10000000) return convert(num / 100000) + ' Lakh ' + (num % 100000 > 0 ? '' + convert(num % 100000) : '');
      if (num < 100000000) return units[Math.trunc(num / 10000000)] + ' Crore ' + (num % 10000000 > 0 ? '' + convert(num % 10000000) : '');
      if (num < 1000000000) return convert(num / 10000000) + 'Crore ' + (num % 10000000 > 0 ? '' + convert(num % 10000000) : '');
      return 'Sorry, Too Big';
    }
    let amountInWord = convert(amount);
    let decimalPart = amountInWord !== 'Sorry, Too Big' ? amount.toString().split(".") : '';
    if (!isNullEmptyUndefinedObject(decimalPart[1])) {
      let fraction = decimalPart[1].split("");
      let decimalPlaces = '';
      if (!isNullEmptyUndefinedObject(fraction)) {
        for (let i = 0; i < fraction.length; i++) {
          let num = units[parseInt(fraction[i])];
          decimalPlaces = i === 0 ? 'point ' + num : decimalPlaces + ' ' + num;
        }
        amountInWord = amountInWord + decimalPlaces;
      }
    }
    return amountInWord + ' Only';
  }

  onclickHandleCancel() {

    this.dispatchEvent(new CustomEvent('cancelled', { detail: { 'message': 'Operation Cancelled' } }));
    window.history.back();
  }

  onclickHandleEdit() {

    this.readMode = false;
    window.scrollTo(0, 0);
    this.getInvoiceFromOrder();
  }

  onclickHandleInvoiceSave() {
    const selectedInvoiceDate = this.invoiceInfo.Invoice_Date__c;
    const todayStr = this.getTodayDateString();
    const earliestStr = this.getEarliestAllowedDate();

    if (selectedInvoiceDate > todayStr) {
      this.dispatchEvent(showToast('Error', 'Invoice Date cannot be in the future.', [], 'error', 'sticky'));
      return;
    }

    if (selectedInvoiceDate < earliestStr) {
      const isOrderDateBinding = this.lastValidInvoiceDate && earliestStr === this.lastValidInvoiceDate;
      const message = isOrderDateBinding ?
      `Invoice Date cannot be before the Order Date (${this.formatDateForDisplay(this.lastValidInvoiceDate)}).` :
      `Invoice Date cannot be more than 3 days in the past. Earliest allowed date is ${this.formatDateForDisplay(earliestStr)}.`;
      this.dispatchEvent(showToast('Error', message, [], 'error', 'sticky'));
      return;
    }

    this.invoiceLineItemsInfo = [...this.itemList];
    const insufficientStockItems = this.itemList.filter((item) => item.Quantity__c > item.CurrentStock);
    if (insufficientStockItems.length > 0) {
      this.dispatchEvent(showToast(
        'Error',
        'Some items in your invoice exceed the available stock. Please adjust the quantities before proceeding.',
        [], 'error', 'sticky'
      ));
      return;
    }
    const discount2Raw = this.invoiceInfo.Discount_2__c;
    const discount2 = Number(discount2Raw);
    if (discount2Raw !== '' && discount2Raw !== null && discount2Raw !== undefined) {
      if (isNaN(discount2) || discount2 < 0 || discount2 > 100) {
        this.dispatchEvent(showToast('Error', 'Please enter a valid Discount 2 between 1 and 100.', [], 'error', 'sticky'));
        return;
      }
    }

    this.invoiceLineItemsInfo = this.itemList.map((item) => ({
      Id: item.Id,
      Invoice__c: this.invoiceInfo.Id,
      Product__c: item.Product__c,
      Quantity__c: item.Quantity__c,
      Price__c: item.Price__c,
      Total_Amount__c: item.Total_Amount__c,
      MRP__c: item.mrp || item.MRP__c || 0,
      Discount_1__c: item.discount1Amt != null && item.discount1Amt !== '' ? item.discount1Amt : 0,
      Discount_2__c: item.discount2Amt != null && item.discount2Amt !== '' ? item.discount2Amt : 0,
      SKU_Discount_Percent__c: item.SKU_Discount_Percent__c || 0,
      Scheme_Discount_Amount__c: item.schemeDiscountAmt != null && item.schemeDiscountAmt !== '' ? item.schemeDiscountAmt : 0,
      Is_Promotional__c: item.isPromotional === true,
      Quantity_Scheme_Applied__c: item.selectedSchemeId || null,
      Promo_Min_Qty__c: item.Promo_Min_Qty__c || item.promoMinQty || null,
      Parent_Product__c: item.parentProductId || null
    }));

    if (this.ValueSchemeExist && this.valueSchemFinalId) {
      this.invoiceInfo.Value_Scheme_Applied__c = this.valueSchemFinalId;
      this.invoiceInfo.Value_Scheme_Discount__c = this.roundNum(this.invoiceInfo.Value_Scheme_Discount__c || 0);
    } else {
      this.invoiceInfo.Value_Scheme_Applied__c = null;
      this.invoiceInfo.Value_Scheme_Discount__c = 0;
    }

    this.isSaving = true;
    saveInvoiceAndItems({
      invoice: this.invoiceInfo,
      invItemList: this.invoiceLineItemsInfo,
      deletedItemIds: this.deletedItemIds
    }).then((result) => {

      if (!isNullEmptyUndefinedObject(result)) {

        // ── Multi-Scheme Retailer Reimbursement — persist current selection ──
        const appliedLines = (this.activeSchemes || [])
          .filter((s) => s.isApplied && s.amountApplied > 0)
          .map((s) => ({ allocationId: s.allocationId, amount: s.amountApplied }));
        saveAppliedLines({
          invoiceId: result.invoice.Id,
          appliedLinesJson: JSON.stringify(appliedLines)
        }).catch(() => { /* non-blocking — invoice save already succeeded */ });

        this.dispatchEvent(showToast('Success', 'Invoice And Invoice Line Items Saved Successfully', [], 'success', ''));
        this[NavigationMixin.Navigate]({
          type: 'standard__recordPage',
          attributes: { recordId: result.invoice.Id, objectApiName: 'Invoice__c', actionName: 'view' }
        });
      }
    }).catch((error) => {
      this.dispatchEvent(showToast('Error', 'Error while saving...' + error.body.message, [], 'error', 'sticky'));
      return '';
    });

    return 'Success';
  }

  navigateToRecordPage() {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId: this.recordId, objectApiName: 'Invoice__c', actionName: 'view' }
    });
  }

  openQuantitySchemeFromInvoice(row) {
    this.isCartContext = true;
    this.activeProductId = row.Product__c;
    this.selectedSchemeId = null;
    getqualitySchemeFromOrder({ productId: row.Product__c, invoiceId: this.recordId }).
    then((result) => {
      const currentQty = row.Quantity__c;
      this.schemeDetails = (Array.isArray(result) ? result : []).map((s) => ({ ...s, isDisabled: currentQty < s.minQty }));
      this.isQualityScheme = true;
    }).
    catch((err) => {

      this.schemeDetails = [];
      this.isQualityScheme = true;
    });
  }

  get hasSchemes() {return this.schemeDetails && this.schemeDetails.length > 0;}

  closeQualitySchemeDialog() {this.isQualityScheme = false;}

  handleSchemeSelection(event) {
    const selectedId = event.target.value;
    this.selectedSchemeId = selectedId;
    this.schemeDetails = this.schemeDetails.map((s) => ({ ...s, isSelected: s.schemeId === selectedId }));
  }

  get isApplyDisabled() {return !this.selectedSchemeId;}

  applyScheme() {
    if (!this.selectedSchemeId || !this.activeProductId) {
      this.dispatchEvent(showToast('Error', 'Please select a scheme', [], 'error', ''));
      return;
    }

    // Purchase Quantity Discount schemes never add a bonus/promo line — the shared
    // Apex (SchemeEvaluationService.applyQuantityScheme) deliberately returns an empty
    // list for this type, which would otherwise look like "no promo applicable" below
    // and silently do nothing. Apply it directly here instead, same as the order cart's
    // applyScheme() does — no Apex round-trip needed since there's no bonus line to
    // resolve, just the line's own schemeDiscountAmt.
    const selectedSchemeDetail = (this.schemeDetails || []).find(
      (s) => s.schemeId === this.selectedSchemeId
    );
    if (selectedSchemeDetail?.schemeType === 'Purchase Quantity Discount') {
      const baseProductId = this.activeProductId;
      const cleanedList = this.itemList.filter(
        (row) => !(row.isPromotional && row.parentProductId === baseProductId)
      );
      const baseItem = cleanedList.find(
        (row) => row.Product__c === baseProductId && !row.isPromotional
      );

      if (!baseItem) {
        this.dispatchEvent(showToast('Error', 'Could not find the line item to apply the scheme to', [], 'error', ''));
        return;
      }

      const discountPercent = Number(selectedSchemeDetail.discountPercentage) || 0;
      baseItem.selectedSchemeId = this.selectedSchemeId;
      baseItem.schemeType = selectedSchemeDetail.schemeType;
      baseItem.Quantity_Scheme_Applied__r = {
        Name: selectedSchemeDetail.schemeName,
        Discount_Percentage__c: discountPercent,
        Type__c: selectedSchemeDetail.schemeType
      };
      baseItem.schemeDiscountAmt = (
        (Number(baseItem.Quantity__c) || 0) * (Number(baseItem.Price__c) || 0) * discountPercent / 100
      ).toFixed(2);

      this.itemList = [...this.recalculatePromoLocks(cleanedList)];
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
      this.isQualityScheme = false;

      this.dispatchEvent(showToast('Success', 'Quantity scheme applied', [], 'success', ''));
      return;
    }

    this.isLoading = true;
    const normalizedItems = this.itemList.
    filter((r) => !r.isPromotional).
    map((row) => ({
      productId: row.Product__c, quantity: row.Quantity__c,
      productOfferPrice: row.Price__c, productName: row.ProductName,
      productFullName: row.ProductName, availableStockQuantity: row.CurrentStock || 0,
      productBrand: '', prodmeasure: '', hsn: INVOICE_HSN_LABEL, mrp: row.MRP__c
    }));
    applyQuantitySchemeFromOrder({ cartItems: normalizedItems, invoiceId: this.recordId, selectedSchemeId: this.selectedSchemeId }).
    then((promoLines) => {
      if (!promoLines || promoLines.length === 0) {
        this.dispatchEvent(showToast('Info', 'No promotional items applicable', [], 'info', ''));
        this.isQualityScheme = false;
        return;
      }
      const baseProductId = this.activeProductId;
      let cleanedList = this.itemList.filter((row) => !(row.isPromotional && row.parentProductId === baseProductId));
      const baseIndex = cleanedList.findIndex((row) => row.Product__c === baseProductId && !row.isPromotional);
      cleanedList[baseIndex].selectedSchemeId = this.selectedSchemeId;
      if (baseIndex === -1) {return;}
      promoLines.forEach((promo, idx) => {
        const originalRate = promo.productListPrice;
        const qty = promo.quantity;
        let grossAmount = 0,discountAmt = 0;
        const isFreeProduct = promo.discountPercentage === null || promo.discountPercentage === 100;
        if (!isFreeProduct) {
          grossAmount = originalRate * qty;
          discountAmt = grossAmount - (promo.unittotalPrice || 0);
        }
        const promoRow = {
          Product__c: promo.productId, Parent_Product__c: baseProductId,
          ProductName: `🎁 ${promo.productName}`, Quantity__c: qty,
          Price__c: originalRate, mrp: promo.mrp,
          Total_Amount__c: grossAmount, discount1Amt: this.roundNum(discountAmt), discount2Amt: 0,
          hsn: promo.hsn || '', CurrentStock: promo.availableStockQuantity || 0,
          Is_Promotional__c: true, Quantity_Scheme_Applied__c: this.selectedSchemeId,
          Promo_Min_Qty__c: promo.promoMinQty,
          isPromotional: true, parentProductId: baseProductId,
          selectedSchemeId: this.selectedSchemeId, isReadOnly: true,
          promoMinQty: promo.promoMinQty, isFreePromo: isFreeProduct
        };
        cleanedList.splice(baseIndex + 1 + idx, 0, promoRow);
      });
      cleanedList = this.recalculatePromoLocks(cleanedList);
      cleanedList.forEach((row, i) => row.rowNo = i + 1);
      const baseItem = cleanedList.find((i) => i.Product__c === baseProductId && !i.isPromotional);
      if (baseItem) baseItem.selectedSchemeId = this.selectedSchemeId;
      this.itemList = [...cleanedList];
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
      this.removeInvalidValueSchemeFromInvoice();
      this.isQualityScheme = false;
      this.dispatchEvent(showToast('Success', 'Quantity scheme applied', [], 'success', ''));
      this.applyStockValidationUI();
    }).
    catch((err) => {

      this.dispatchEvent(showToast('Error', err?.body?.message || 'Failed to apply scheme', [], 'error', ''));
    }).
    finally(() => {this.isLoading = false;});
  }

  recalculatePromoLocks(list) {
    const baseIdsWithPromo = new Set(list.filter((r) => r.isPromotional).map((r) => r.parentProductId));
    return list.map((row) => {
      const isBaseWithPromo = !row.isPromotional && baseIdsWithPromo.has(row.Product__c);
      return { ...row, hasPromoChild: isBaseWithPromo, deleteTooltip: isBaseWithPromo ? 'Remove promo item first' : 'Delete' };
    });
  }

  closeValueSchemeDialog() {this.isValueScheme = false;this.openCart = true;}

  removeInvalidPromosFromInvoice(editedProductId) {
    const baseRow = this.itemList.find((r) => !r.isPromotional && r.Product__c === editedProductId);
    if (!baseRow) return;
    const baseQty = Number(baseRow.Quantity__c) || 0;
    const before = this.itemList.length;
    let cleaned = this.itemList.filter((item) => {
      if (!item.isPromotional) return true;
      if (item.promoType === 'VALUE') return true;
      const realParentId = item.parentProductId ||
      this.itemList.find((r) => !r.isPromotional && r.selectedSchemeId === item.selectedSchemeId)?.Product__c;
      if (realParentId !== editedProductId) return true;
      return baseQty >= item.promoMinQty;
    });
    if (cleaned.length !== before) {
      this.itemList = this.recalculatePromoLocks(cleaned);
      this.itemList.forEach((r, i) => r.rowNo = i + 1);
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
      this.dispatchEvent(showToast('Info', 'Promotional items removed as base product quantity changed', [], 'info', ''));
    }
  }

  // Builds one CartLineWrapper (productId, productBrand, lineAmount) per LIVE invoice line
  // item — mirrors secondaryInvoice.js's buildCartLinesForInvoice(). Reads from
  // this.itemList (the current, possibly user-edited working set shown on screen) so a
  // Flat Discount scheme's slab always resolves against what the invoice actually shows
  // right now. See decision log §8.13.
  buildCartLinesForInvoice() {
    return (this.itemList || [])
      .filter((item) => !item.Is_Promotional__c && item.Product__c)
      .map((item) => ({
        productId: item.Product__c,
        productBrand: item.Product_Brand__c || item.Product__r?.Product_Brand__c || '',
        lineAmount: Number(item.Total_Amount__c) || 0
      }));
  }

  openDialogForValueSchemeFromInvoice() {
    const totalInvoiceValue = this.invoiceInfo?.Taxable_Amount__c;
    if (!totalInvoiceValue || !this.recordId) {return;}
    getvalueSchemeFromOrder({
      totalAmount: totalInvoiceValue,
      invoiceId: this.recordId,
      cartLinesJson: JSON.stringify(this.buildCartLinesForInvoice())
    }).
    then((result) => {
      if (result && result.length > 0) {
        if (this.valueSchemFinalId) {
          result = result.map((scheme) => scheme.id === this.valueSchemFinalId ? { ...scheme, isApplied: true } : scheme);
          result.sort((a, b) => (b.isApplied ? 1 : 0) - (a.isApplied ? 1 : 0));
        }
        this.valueSchemeDetails = result;
        this.isValueScheme = true;
        this.isNoSchemesMessage = false;
      } else {
        this.isNoSchemesMessage = true;
        this.isValueScheme = true;
        this.noSchemesMessage = NO_Cart_SCHEME_AVAILABLE;
      }
    }).
    catch((error) => {});
  }

  applyValueSchemeOnInvoice(event) {
    const valueSchemId = event.target.dataset.applyId;
    this.valueSchemFinalId = valueSchemId;

    // Reset the reapplyValueSchemeOnInvoice() guard so the very next quantity change after
    // freshly applying a scheme is always re-checked against Apex.
    this._lastReappliedInvoiceValueSchemeKey = null;

    this.isValueScheme = false;
    this.openCart = true;
    this.clearExistingValueSchemeFromInvoice();
    getAppliedValueSchemeForOrder({
      valueSchemId,
      invoiceId: this.recordId,
      cartTotal: this.grossCartTotal || this.invoiceInfo?.Taxable_Amount__c,
      cartLinesJson: JSON.stringify(this.buildCartLinesForInvoice())
    }).
    then((result) => {
      this.valueSchemeThreshold = result.cartAmount;
      localStorage.setItem('valueSchemeThreshold', this.valueSchemeThreshold);
      this.ValueSchemeExist = true;
      this.getAppliedValueSchemeNameMethod();
      this.valueSchemeQualifyingSubtotal = result.qualifyingSubtotal != null ?
        result.qualifyingSubtotal : null;
      if (result.discountAmount != null) {
        this.discountAmountGiven = result.discountAmount;
        this.discountPercemtageGivenCheck = false;
        this.discountAmountGivenCheck = true;
      } else if (result.discountPercentage != null) {
        this.discountPercemtageGiven = result.discountPercentage;
        this.discountAmountGivenCheck = false;
        this.discountPercemtageGivenCheck = true;
      }
      if (result.schemeType === 'Free Product' && result.freeProductId) {
        this.addValuePromoProductToInvoice(result.freeProductId, result.promoQty || 1);
      }
      this.skipValueSchemeValidationOnce = true;
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
      this.dispatchEvent(showToast('Success', 'Value scheme applied on invoice', [], 'success', ''));
    }).
    catch((error) => {});
  }

  restoreValueSchemeThreshold() {
    if (!this.valueSchemFinalId) return;
    getAppliedValueSchemeForOrder({
      valueSchemId: this.valueSchemFinalId,
      invoiceId: this.recordId,
      cartTotal: this.grossCartTotal || this.invoiceInfo?.Taxable_Amount__c,
      cartLinesJson: JSON.stringify(this.buildCartLinesForInvoice())
    }).
    then((result) => {
      this.valueSchemeThreshold = result.cartAmount;
      this.valueSchemeQualifyingSubtotal = result.qualifyingSubtotal != null ?
        result.qualifyingSubtotal : null;
      if (result.discountAmount != null) {
        this.discountAmountGiven = result.discountAmount;
        this.discountAmountGivenCheck = true;
        this.discountPercemtageGivenCheck = false;
      } else if (result.discountPercentage != null) {
        this.discountPercemtageGiven = result.discountPercentage;
        this.discountPercemtageGivenCheck = true;
        this.discountAmountGivenCheck = false;
      }
      this.handlePriceCalculations();

    }).
    catch((err) => {});
  }

  addValuePromoProductToInvoice(productId, promoQty) {
    if (this.itemList.some((r) => r.isPromotional && r.Product__c === productId)) return;
    getProductForValueScheme({ productId }).
    then((product) => {
      const promoRow = {
        Product__c: product.productId, ProductName: `🎁 ${product.productName}`,
        Quantity__c: promoQty, Price__c: product.productOfferPrice || 0,
        mrp: product.mrp || 0, Total_Amount__c: 0,
        discount1Amt: 0, discount2Amt: 0,
        hsn: product?.hsn || '', CurrentStock: product.availableStockQuantity || 0,
        Is_Promotional__c: true, Quantity_Scheme_Applied__c: null,
        Promo_Min_Qty__c: 0, isPromotional: true, promoType: 'VALUE',
        parentProductId: null, isReadOnly: true
      };
      this.itemList.push(promoRow);
      this.itemList.forEach((r, i) => r.rowNo = i + 1);
      this.itemList = [...this.itemList];
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
    }).
    catch((error) => {});
  }

  getAppliedValueSchemeNameMethod() {
    getAppliedValueSchemeName({ valueSchemActiveId: this.valueSchemFinalId }).
    then((result) => {
      if (result != null && result !== '' && result != undefined) {
        this.ValueSchemeExist = true;
        this.ValueSchemeFinalName = result;
        localStorage.setItem('ValueSchemeFinalName', this.ValueSchemeFinalName.toString());
        localStorage.setItem('ValueSchemeExist', this.ValueSchemeExist.toString());
      }
    }).
    catch((error) => {});
  }

  // Re-evaluates the currently applied Value Scheme's discount against the CURRENT cart
  // total/lines — called on every handlePriceCalculations() pass once a scheme is applied.
  // For Flat Discount schemes this lets the discount move to a lower OR higher
  // Scheme_Slab__c as quantities change, instead of staying stuck on whatever % it had when
  // "Apply" was last clicked. Mirrors secondaryInvoice.js's reapplyValueSchemeOnInvoice().
  // See decision log §8.5/§8.13.
  reapplyValueSchemeOnInvoice() {
    if (!this.ValueSchemeExist || !this.valueSchemFinalId) return;

    // Guard against re-entrant loops: this method's own success path calls
    // handlePriceCalculations() again to push the recalculated discount into the totals,
    // which would otherwise re-enter this same method. Skip the Apex round-trip when
    // neither the applied scheme nor the cart total has actually changed since last check.
    const reapplyKey = this.valueSchemFinalId + '|' + this.grossCartTotal;
    if (this._lastReappliedInvoiceValueSchemeKey === reapplyKey) return;
    this._lastReappliedInvoiceValueSchemeKey = reapplyKey;

    getAppliedValueSchemeForOrder({
      valueSchemId: this.valueSchemFinalId,
      invoiceId: this.recordId,
      cartTotal: this.grossCartTotal || this.invoiceInfo?.Taxable_Amount__c,
      cartLinesJson: JSON.stringify(this.buildCartLinesForInvoice())
    }).
    then((result) => {
      const hasDiscountAmount = result.discountAmount != null;
      const hasDiscountPercentage = result.discountPercentage != null;

      if (!hasDiscountAmount && !hasDiscountPercentage) {
        // No Scheme_Slab__c qualifies at the new cart total (dropped below the scheme's
        // lowest tier) — remove the scheme entirely.
        this.itemList = this.itemList.filter(
          (item) => !(item.isPromotional && item.promoType === 'VALUE')
        );
        this.clearValueScheme();
        this.itemList.forEach((r, i) => r.rowNo = i + 1);
        this.itemList = [...this.itemList];
        this.dispatchEvent(
          showToast('Info', 'Value scheme removed as cart total is below threshold', [], 'info', '')
        );
        return;
      }

      this.valueSchemeThreshold = result.cartAmount;
      localStorage.setItem('valueSchemeThreshold', this.valueSchemeThreshold);
      this.valueSchemeQualifyingSubtotal = result.qualifyingSubtotal != null ?
        result.qualifyingSubtotal : null;

      if (hasDiscountAmount) {
        this.discountAmountGiven = result.discountAmount;
        this.discountAmountGivenCheck = true;
        this.discountPercemtageGiven = 0;
        this.discountPercemtageGivenCheck = false;
      } else {
        this.discountPercemtageGiven = result.discountPercentage;
        this.discountPercemtageGivenCheck = true;
        this.discountAmountGiven = 0;
        this.discountAmountGivenCheck = false;
      }

      this.skipValueSchemeValidationOnce = true;
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
    }).
    catch((error) => {
      console.error('Error in reapplyValueSchemeOnInvoice:', error);
    });
  }

  clearExistingValueSchemeFromInvoice() {
    this.itemList = this.itemList.filter((row) => !(row.isPromotional && row.promoType === 'VALUE'));
    this.discountAmountGiven = 0;this.discountPercemtageGiven = 0;
    this.discountAmountGivenCheck = false;this.discountPercemtageGivenCheck = false;
    this.invoiceInfo.Value_Scheme_Applied__c = null;
    this.invoiceInfo.Value_Scheme_Discount__c = 0;
    this.itemList.forEach((r, i) => r.rowNo = i + 1);
    this.itemList = [...this.itemList];
  }

  clearValueScheme() {
    this.ValueSchemeExist = false;this.ValueSchemeFinalName = '';
    this.valueSchemFinalId = '';this.valueSchemeThreshold = null;
    this.valueSchemeQualifyingSubtotal = null;
    this.discountAmountGiven = 0;this.discountPercemtageGiven = 0;
    this.discountAmountGivenCheck = false;this.discountPercemtageGivenCheck = false;
    this.invoiceInfo.Value_Scheme_Applied__c = null;
    this.invoiceInfo.Value_Scheme_Discount__c = 0;

    localStorage.removeItem('valueSchemFinalId');
    localStorage.removeItem('valueSchemeThreshold');
  }

  removeInvalidValueSchemeFromInvoice() {
    const hasValuePromo = this.itemList.some((item) => item.isPromotional && item.promoType === 'VALUE');



    if (this.skipValueSchemeValidationOnce) {this.skipValueSchemeValidationOnce = false;return;}
    if (this.ValueSchemeExist && !hasValuePromo) {this.clearValueScheme();return;}
    if (!this.ValueSchemeExist) return;
    if (this.valueSchemeThreshold == null) return;
    if (this.grossCartTotal < this.valueSchemeThreshold) {
      this.itemList = this.itemList.filter((item) => !(item.isPromotional && item.promoType === 'VALUE'));
      this.clearValueScheme();
      this.itemList.forEach((r, i) => r.rowNo = i + 1);
      this.itemList = [...this.itemList];
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
      this.dispatchEvent(showToast('Info', 'Value scheme removed as cart total is below threshold', [], 'info', ''));
    }
  }

  getProductStockUsageMap() {
    const usageMap = new Map();
    this.itemList.forEach((item) => {
      const pid = item.Product__c,qty = Number(item.Quantity__c) || 0;
      if (!usageMap.has(pid)) usageMap.set(pid, { used: 0, stock: Number(item.CurrentStock) || 0 });
      usageMap.get(pid).used += qty;
    });
    return usageMap;
  }

  applyStockValidationUI() {
    const stockMap = this.getProductStockUsageMap();
    this.itemList = this.itemList.map((item) => {
      const stockInfo = stockMap.get(item.Product__c);
      const isOver = stockInfo.used > stockInfo.stock;
      return { ...item, quantityCellClass: isOver ? 'background-color: #fff8c4; color: #7a6600;' : '' };
    });
  }

  reapplyQuantitySchemeFromInvoice(baseProductId) {
    const baseRow = this.itemList.find((r) => !r.isPromotional && r.Product__c === baseProductId);
    if (!baseRow || !baseRow.selectedSchemeId) return;
    const oldPromos = this.itemList.filter((r) => r.isPromotional && r.parentProductId === baseProductId);
    const normalizedItems = this.itemList.filter((r) => !r.isPromotional).map((row) => ({
      productId: row.Product__c, quantity: row.Quantity__c,
      productOfferPrice: row.Price__c, productName: row.ProductName,
      productFullName: row.ProductName, availableStockQuantity: row.CurrentStock || 0,
      productBrand: '', prodmeasure: '', hsn: INVOICE_HSN_LABEL, mrp: row.MRP__c
    }));
    applyQuantitySchemeFromOrder({
      cartItems: normalizedItems, invoiceId: this.recordId,
      selectedSchemeId: baseRow.selectedSchemeId
    }).
    then((promoLines) => {
      let cleaned = this.itemList.filter((r) => !(r.isPromotional && r.parentProductId === baseProductId));
      const baseIndex = cleaned.findIndex((r) => !r.isPromotional && r.Product__c === baseProductId);
      if (baseIndex === -1) return;
      promoLines.forEach((promo, idx) => {
        const existing = oldPromos.find((p) =>
        p.Product__c === promo.productId && p.selectedSchemeId === baseRow.selectedSchemeId);
        const isFree = promo.discountPercentage === null || promo.discountPercentage === 100 || promo.unittotalPrice === 0;
        let totalAmount = 0,discountAmt = 0;
        if (!isFree) {
          const gross = promo.productListPrice * promo.quantity;
          totalAmount = gross;discountAmt = gross - (promo.unittotalPrice || 0);
        }
        cleaned.splice(baseIndex + 1 + idx, 0, {
          Id: existing?.Id,
          Product__c: promo.productId, Parent_Product__c: baseProductId,
          ProductName: `🎁 ${promo.productName}`, Quantity__c: promo.quantity,
          Price__c: promo.productListPrice, mrp: promo.mrp,
          Total_Amount__c: totalAmount, discount1Amt: this.roundNum(discountAmt), discount2Amt: 0,
          hsn: promo.hsn || '', CurrentStock: promo.availableStockQuantity || 0,
          isPromotional: true, parentProductId: baseProductId,
          selectedSchemeId: baseRow.selectedSchemeId, isReadOnly: true,
          promoMinQty: promo.promoMinQty, isFreePromo: isFree
        });
      });
      cleaned = this.recalculatePromoLocks(cleaned);
      cleaned.forEach((r, i) => r.rowNo = i + 1);
      this.itemList = [...cleaned];
      this.recalculateDiscountTotals();
      this.handlePriceCalculations();
    });
  }
}