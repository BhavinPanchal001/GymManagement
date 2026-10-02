# TASK-02: Enforce Unique Card Numbers and Duplicate Member Warnings

## Priority: Critical
## Category: Data Integrity & Registration Workflow

---

## 1. Problem Statement
In real-world gym operations, member identification relies on physical access cards, RFID tags, or assigned membership numbers (e.g. Card #101, #102).
Currently:
- In [add_customer_sheet.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/customers/add_customer_sheet.dart#L391), the card number input field has zero uniqueness validation.
- In [gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L513), `addCustomer()` accepts any card number without checking if an existing member already holds it.
- In addition, two members can be registered with the exact same phone number without any confirmation or warning. While families (e.g. parent and teen) may legitimately share a contact number, owners frequently enter the same member twice by accident when searching is missed.

---

## 2. Goals & Objectives
1. **Strict Card Number Uniqueness**:
   - Every member must have a unique non-empty card number.
   - The form must validate card number availability in real-time or upon form submission.
   - If a duplicate card number is entered, show a clear error message: *"Card #[number] is already assigned to [Member Name]"*.
2. **Phone Number Duplicate Warning**:
   - When entering a phone number that matches an existing member, prompt the owner with an informative warning dialog:
     *"A member named [Existing Member] (Card #[Existing Card]) is already registered with this phone number. Is this a family member sharing the number?"*
   - Allow the owner to either continue (if intentional) or cancel (if accidental duplicate).
3. **Robust Auto-Numbering**:
   - Improve `getNextCardNumber()` to guarantee it never suggests a card number that is already in use.

---

## 3. Impacted Files
- [lib/services/gym_service.dart — `addCustomer()` and `getNextCardNumber()`](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L445-L555)
- [lib/services/gym_service.dart — `updateCustomer()`](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L755-L764)
- [lib/screens/customers/add_customer_sheet.dart — card number field](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/customers/add_customer_sheet.dart#L391-L401)
- [lib/screens/customers/add_customer_sheet.dart — `_saveCustomer()` submit handler](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/customers/add_customer_sheet.dart#L178-L224)
- [lib/screens/customers/customer_detail_screen.dart — edit trigger at line 124](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/customers/customer_detail_screen.dart#L120-L128)

---

## 4. Detailed Implementation Steps

### Step 1: Add Integrity Checks in `GymService`
- Implement `Customer? getCustomerByCardNumber(String cardNumber, {String? excludeCustomerId})`:
  - Trims input and performs case-insensitive comparison against `_customers`.
  - Skips `excludeCustomerId` when editing an existing member.
- Implement `List<Customer> getCustomersByPhone(String phone, {String? excludeCustomerId})`:
  - Normalizes phone numbers (strips spaces, dashes, leading +91/0) and finds matches.
- Update `getNextCardNumber()`:
  - Scans all numeric card numbers, identifies the highest allocated integer, and returns `max + 1`.
  - Verifies that the candidate number is not already assigned (even if non-numeric prefixes exist).

### Step 2: Form Validation in `add_customer_sheet.dart`
- In `_cardNumberController`:
  - Add validator in `TextFormField` (at line 391):
    ```dart
    validator: (value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return 'Card number is required';
      final existing = gymService.getCustomerByCardNumber(trimmed, excludeCustomerId: widget.customerToEdit?.id);
      if (existing != null) {
        return 'Already assigned to ${existing.name}';
      }
      return null;
    }
    ```
- In `_saveCustomer()` (at line 178 — NOT `_handleSubmit` which doesn't exist):
  - Before saving, check `gymService.getCustomersByPhone(enteredPhone, excludeCustomerId: ...)`.
  - If matches exist, display an `AlertDialog`:
    - Title: `"Duplicate Phone Number"`
    - Content: Details of the matching member(s).
    - Actions: `"Cancel & Review"` and `"Yes, Add Member"`.

### Step 3: Edit Member Safeguards in `add_customer_sheet.dart` (Edit Mode)
- The edit flow is triggered from `customer_detail_screen.dart` line 124 which calls `AddCustomerSheet.show(context, customerToEdit: customer)`. This opens the **same** `AddCustomerSheet` in edit mode (`isEditing == true`).
- In edit mode, `_saveCustomer()` calls `GymService().updateCustomer(updated)` at line 202.
- Ensure `updateCustomer()` in `GymService` (line 755) also validates card number uniqueness before saving — either by adding validation inside `updateCustomer()` itself, or by ensuring the form validator runs the same `excludeCustomerId` logic when editing.

---

## 5. Edge Cases & Considerations
- **Alphanumeric Card Numbers**: Support both purely numeric IDs (`101`, `102`) and alphanumeric tags (`VIP-01`, `FIT-99`).
- **Archived / Inactive Members**: Inactive members must still hold their card numbers to prevent physical card collisions unless their card is explicitly re-assigned.
- **Whitespace & Formatting**: Always trim input before comparison (`" 105 "` vs `"105"`).

---

## 6. Validation & Testing Checklist
- [ ] Attempt to register a new member with an existing card number: verify submission is blocked with an inline error.
- [ ] Edit an existing member without changing their card number: verify it saves successfully without self-collision.
- [ ] Enter a phone number matching an existing member: verify the warning dialog appears with the correct member name.
- [ ] Verify that tapping "Cancel & Review" aborts registration, while "Yes, Add Member" completes it.
- [ ] Confirm `getNextCardNumber()` increments properly and never collides with manually assigned card numbers.
