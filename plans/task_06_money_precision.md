# TASK-06: Standardize Money & Pricing Decimal Precision

## Priority: High
## Category: Financial Accuracy & Data Integrity

---

## 1. Problem Statement
Throughout several screens in the application, financial amounts and membership fees are converted to whole integers using `.toInt()` when initializing text controllers:
- In [edit_profile_screen.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/edit_profile_screen.dart#L56):
  `text: p.price.toInt().toString()`
- In [mark_payment_dialog.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/widgets/mark_payment_dialog.dart#L93):
  `text: initialAmount.toInt().toString()`
- **Loss of Financial Data**: If a gym charges an amount with decimals (such as ₹499.50, ₹600.75, or fractional tax-inclusive totals), opening and saving the editing dialog silently strips the decimals and turns it into ₹499 or ₹600.
- Over time, these truncations create persistent accounting discrepancies between actual receipts, cash drawers, and recorded reports.

---

## 2. Goals & Objectives
1. **Preserve Decimal Precision Across All Financial Fields**:
   - Never truncate decimal currency values with `.toInt()`.
   - Implement a standardized money input formatter and string converter:
     - If the number is whole (e.g. `600.0`), display cleanly as `"600"`.
     - If the number has fractional paise/cents (e.g. `600.75`), display cleanly as `"600.75"`.
2. **Support Decimal Input Everywhere**:
   - Ensure all amount input fields use `TextInputType.numberWithOptions(decimal: true)`.
   - Parse values strictly using `double.tryParse()` rather than integer parsing.
3. **Guard Against Invalid & Negative Values**:
   - Prevent negative payments (`amount <= 0`) from being recorded as paid.
   - Guard against invalid non-numeric strings falling back to random numbers.

---

## 3. Impacted Files
- [lib/utils/date_utils.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/utils/date_utils.dart#L1) (or a dedicated `format_utils.dart`)
- [lib/screens/settings/edit_profile_screen.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/edit_profile_screen.dart#L56)
- [lib/widgets/mark_payment_dialog.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/widgets/mark_payment_dialog.dart#L92-L95)
- [lib/screens/settings/settings_tab.dart — fee input fields](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/settings_tab.dart#L700-L760) *(note: the plan previously cited L50-L75, but the actual fee text fields with `TextInputType.number` are at L700+)*
- [lib/screens/billing/expense_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/billing/expense_tab.dart#L1-L100)
- [lib/widgets/add_expense_dialog.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/widgets/add_expense_dialog.dart) *(expense amount input is in this separate dialog widget, NOT in expense_tab.dart)*

---

## 4. Detailed Implementation Steps

### Step 1: Create a Central Currency Helper
- In a shared utility class, define:
  ```dart
  class MoneyUtils {
    /// Formats an amount for editing fields without losing precision.
    /// 600.0 -> "600"
    /// 600.5 -> "600.50"
    /// 600.75 -> "600.75"
    static String formatForInput(double amount) {
      if (amount % 1 == 0) {
        return amount.toInt().toString();
      }
      return amount.toStringAsFixed(2);
    }

    /// Formats an amount for display with currency symbol: e.g. "₹600" or "₹600.50"
    static String formatDisplay(double amount, {String symbol = '₹'}) {
      if (amount % 1 == 0) {
        return '$symbol${amount.toInt()}';
      }
      return '$symbol${amount.toStringAsFixed(2)}';
    }

    /// Safe double parser
    static double parseAmount(String? text, {double defaultValue = 0.0}) {
      if (text == null) return defaultValue;
      final cleaned = text.replaceAll(RegExp(r'[^\d.]'), '');
      return double.tryParse(cleaned) ?? defaultValue;
    }
  }
  ```

### Step 2: Replace Truncations in `edit_profile_screen.dart` and `settings_tab.dart`
- In `edit_profile_screen.dart` (line 56): Replace `p.price.toInt().toString()` with `MoneyUtils.formatForInput(p.price)`.
- In `settings_tab.dart` (lines 700-760): The fee input fields use `TextInputType.number` which does NOT allow decimal input. Change to `TextInputType.numberWithOptions(decimal: true)` on all three fee `TextField` widgets (Normal, PT, PT+Diet).
- Use `MoneyUtils.parseAmount(_packageControllers[p.id]?.text)` when saving.

### Step 3: Replace Truncations in `mark_payment_dialog.dart`
- Replace `initialAmount.toInt().toString()` with `MoneyUtils.formatForInput(initialAmount)`.
- Ensure the amount input validator enforces:
  - Required field.
  - Positive number > 0 (unless explicit zero-fee free pass is selected).
  - Valid decimal format with at most 2 decimal places.

### Step 4: Audit Expense Dialogs
- Expense amounts are entered in [add_expense_dialog.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/widgets/add_expense_dialog.dart), NOT `expense_tab.dart` (which only displays expenses). Ensure the expense amount input field in `add_expense_dialog.dart` supports decimals (e.g. electricity bills or equipment maintenance like ₹1450.50) and uses `MoneyUtils.formatForInput()` for initialization.

---

## 5. Edge Cases & Considerations
- **Multiple Decimal Points**: Prevent users from typing invalid strings like `12.34.56` using regex filtering.
- **Locale Comma vs Dot**: In locales where comma is used as decimal separator, normalize `,` to `.` during parsing.
- **Rounding in Reports**: When aggregating sums of doubles, ensure floating-point precision artifacts (e.g. `0.1 + 0.2 = 0.30000000000000004`) are rounded to 2 decimal places in financial summaries.

---

## 6. Validation & Testing Checklist
- [ ] Set a plan price to ₹650.50 in Settings: verify saving and reopening maintains ₹650.50 without rounding to ₹650.
- [ ] Open the payment dialog for a member: enter ₹750.25: verify the receipt records ₹750.25 accurately.
- [ ] Check the collections total in Billing: verify the sum includes the ₹0.25 decimal without dropping or drifting.
- [ ] Try typing `-50` or `0` in payment dialog: verify validation error blocks saving invalid amounts.
