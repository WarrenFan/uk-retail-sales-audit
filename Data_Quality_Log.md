# Data Quality & Audit Log: UK Online Retail Dataset (2009–2011)

This log records the data cleansing hierarchy, non-product code exclusions, anomaly classifications, and catalog boundary cases identified in the UCI Online Retail II dataset.

---

## 1. Cleansing Hierarchy & Exclusions Summary
Cleaning rules were applied in strict sequential order. Each row was eliminated in exactly one step so that control totals reconcile with zero variance:

| Step | Rule Applied | Rows Removed | Excluded Value (£) | Business Rationale |
| :---: | :--- | :---: | :---: | :--- |
| **Step 1** | Exact Duplicates | 34,335 | £431,716.87 | Identical rows across all 8 columns, most likely resulting from system transmission or double-entry errors. |
| **Step 2** | Non-Product Codes | 5,980 | £87,943.66 | Freight, postal fees, platform commissions, manual adjustments, and bad debt. |
| **Step 3** | Data Anomalies | 5,928 | £0.00 | Zero or negative unit prices, most likely stock adjustments. |
| **=** | **Total Excluded** | **46,243** | **£519,660.53** | Exact variance between raw baseline and cleaned dataset. |

---

## 2. Identified Non-Product StockCodes (Step 2 Breakdown)
Standard catalog SKUs follow a 5-digit pattern (optionally followed by letters). Reviewing all non-matching codes identified the following operational charges and non-standard catalog entries:

| StockCode | Common Description | Row Count | Net Value (£) | Nature / Exclusion Reason |
| :--- | :--- | :---: | :---: | :--- |
| `POST` | POSTAGE | 2,086 | £110,430.41 | Domestic and international customer shipping charges. |
| `DOT` | DOTCOM POSTAGE | 1,425 | £309,844.10 | Online web portal delivery charges. |
| `M` | Manual | 1,392 | -£83,311.28 | Manual ledger corrections/offline credit adjustments. |
| `C2` | CARRIAGE | 277 | £13,136.00 | Bulk freight delivery fees. |
| `D` | Discount | 173 | -£12,879.63 | Commercial trade discounts and customer rebates. |
| `S` | SAMPLES | 101 | -£5,991.11 | Free promotional and marketing product samples. |
| `BANK CHARGES` | Bank Charges | 100 | -£35,482.25 | Banking transaction and merchant processing fees. |
| `ADJUST` | Adjustment | 67 | £6,835.24 | Warehouse inventory count adjustments. |
| `AMAZONFEE` | AMAZON FEE | 36 | -£221,520.50 | Amazon marketplace selling fees and deductions. |
| `Other codes` | Gift vouchers, tokens, legacy items (`DCGS...`, `PADS`) | 323 | £6,882.68 | Minor gift vouchers, legacy novelty items, and non-5-digit catalog entries. |
| **Total Step 2** | **All Non-Product Codes** | **5,980** | **£87,943.66** | **Ties out with Step 2 control total with zero variance.** |

*Boundary Case Notes on Non-Standard Codes*:
* `PADS` ("PADS TO MATCH ALL CUSHIONS", 18 rows) and legacy `DCGS` prefix codes (e.g. `DCGS0058` "MISO PRETTY GUM") appear to represent physical products, but were excluded under the uniform 5-digit SKU rule. Their aggregate financial impact is negligible (< £600) and does not affect the analysis.

---

## 3. Step 3 Anomalies Breakdown
All **5,928 rows** excluded in Step 3 fell under the `Zero or negative price` rule, carrying **£0.00** financial impact:
* **Root Cause**: These entries most likely represent warehouse stock adjustments such as damages, shortages, and discards rather than customer transactions.
* **Evidence from Descriptions**: Multiple entries under valid product codes carried warehouse notes instead of merchandise titles, such as `"Wet, rusty-thrown away"`, `"short"`, or `NULL` descriptions with zero price.
* **Bad Debt Invoices (`Invoice LIKE 'A%'`)**: All 6 bad debt invoices used single-letter code `B` (e.g. `A563185`, "Adjust bad debt") and were eliminated in Step 2 under non-product codes (included in "Other codes" above), leaving Step 3 with purely £0.00 records.

---

## 4. SKU Classification Boundaries (Excluded from ABC-XYZ)
A total of **33 SKUs** were excluded from the final ABC-XYZ matrix:
* **32 SKUs with Net Lifetime Revenue <= £0 (-£527.68)**: These most likely represent items where cancellations recorded in early 2010 tied back to original purchases completed prior to December 2009. Excluded from ABC Pareto ranking to prevent cumulative percentage distortion.
* **1 SKU with Sole Sales in December 2011**: SKU `23843` had sales recorded exclusively in December 2011 and was omitted from the 24-month observation window (Dec 2009 – Nov 2011).

---

## 5. Description Inconsistencies on Identical StockCodes
Certain StockCodes feature multiple descriptions across the two-year period due to catalog revisions and warehouse notations:
* **Example (StockCode `71477`)**: Appears as `"COLOUR GLASS. STAR T-LIGHT HOLDER"` and `"COLOURED GLASS STAR T-LIGHT HOLDER"`.
* **Warehouse Discard Notes Excluded**: Warehouse damage entries under this code (e.g. `"Wet, rusty-thrown away"`) carried a unit price of £0.00 and were filtered out in Step 3. Consequently, in the cleaned dataset, `MAX(Description)` selects only between valid catalog titles, with no risk of selecting warehouse discard notes.

---

## 6. Major Outlier Transactions (B2B Bulk Cancellations)
Two single-order transactions accounted for **£245,653.20 (34.3%)** of all commercial cancellation losses:
1. **Customer `16446` (09-Dec-2011, Invoice `C581484`)**: Order of 80,995 units of `23843` (*PAPER CRAFT, LITTLE BIRDIE*), cancelled 12 minutes after order placement for **£168,469.60**.
2. **Customer `12346` (18-Jan-2011, Invoice `C541433`)**: Order of 74,215 units of `23166` (*MEDIUM CERAMIC TOP STORAGE JAR*), cancelled 16 minutes after order placement for **£77,183.60**.

Both events most likely reflect input errors or immediate order reversals rather than product dissatisfaction. Excluding them adjusts the company's baseline return rate from **3.65%** to an underlying **2.43%**.
