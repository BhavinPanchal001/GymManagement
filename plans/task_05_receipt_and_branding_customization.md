# TASK-05: Configurable Receipts, Gym Timings, and Dynamic Branding

## Priority: High
## Category: Business Setup, Branding & Legal Compliance

---

## 1. Problem Statement
The app currently has numerous hardcoded assumptions about the gym's brand, tax status, and rules:
- **Hardcoded Taxes / GST**: In [payment_receipt_pdf_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/payment_receipt_pdf_service.dart#L765), every PDF receipt prints `'Taxes / GST: Inclusive'` and `'Discount: 0.0'` regardless of whether the gym is GST registered. For small gyms not registered under GST, generating receipts claiming "GST Inclusive" is legally problematic.
- **Hardcoded Terms & Conditions**: In [payment_receipt_pdf_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/payment_receipt_pdf_service.dart#L838), the receipt footer prints 4 static non-refundable policy clauses that the owner cannot adjust.
- **Hardcoded Gym Timings & Fallbacks**: In [whatsapp_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/whatsapp_service.dart#L290-L299), messages fall back to `"IronPulse Fitness Club"` with fixed hours (`6:00 AM – 11:00 AM`).
- **Hardcoded Branding in Splash Screen**: In [splash_screen.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/splash/splash_screen.dart#L172), the app loading screen permanently displays `"IRONPULSE"`, creating an awkward impression for an owner running their own named facility.

---

## 2. Goals & Objectives
1. **Dynamic Gym Profile & Branding**:
   - Allow the gym owner to configure:
     - Gym Name (already partially present, ensure it propagates everywhere)
     - Tagline / Subtitle (e.g. *"Strength & Conditioning Gym"*)
     - Gym Address (printed on receipt headers)
     - Contact Phone & Email
     - Operational Hours / Timings
2. **Owner-Configurable Tax & Receipt Policy**:
   - Provide a toggle: `isTaxEnabled` (default: false for small gyms).
   - If enabled: configure tax label (`GST`, `VAT`, `Sales Tax`), tax percentage, and whether pricing is tax-inclusive or tax-exclusive.
   - If disabled: completely omit the GST row or display tax-exempt status on PDF receipts.
   - Customizable multiline Receipt Terms & Policies field.
3. **Dynamic Splash & WhatsApp Messaging**:
   - The splash screen must display the owner's configured gym name and tagline dynamically.
   - WhatsApp welcome and receipt messages must use the configured gym name and hours.

---

## 3. Impacted Files
- [lib/models/gym_settings.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/models/gym_settings.dart#L5-L195)
- [lib/screens/settings/settings_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/settings_tab.dart#L80-L100)
- [lib/screens/settings/edit_profile_screen.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/settings/edit_profile_screen.dart#L40-L120)
- [lib/services/payment_receipt_pdf_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/payment_receipt_pdf_service.dart#L750-L860)
- [lib/services/whatsapp_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/whatsapp_service.dart#L285-L315)
- [lib/screens/splash/splash_screen.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/splash/splash_screen.dart#L170-L195)

---

## 4. Detailed Implementation Steps

### Step 1: Extend `GymSettings` Model
- Add new properties to `GymSettings`:
  ```dart
  final String gymTagline;
  final String gymAddress;
  final String gymPhone;
  final String gymTimings;
  final bool isTaxEnabled;
  final String taxLabel; // e.g. "GST"
  final double taxRatePercent; // e.g. 18.0
  final bool isTaxInclusive;
  final String receiptTerms;
  ```
- Update `toMap()`, `fromMap()`, `copyWith()`, and provide clean defaults.
- **Migration safety**: When existing users update the app, their stored JSON won't contain the new fields. `fromMap()` (line 161) must provide null-safe defaults:
  ```dart
  gymTagline: map['gymTagline'] as String? ?? 'Gym Management & Billing Suite',
  gymAddress: map['gymAddress'] as String? ?? '',
  gymPhone: map['gymPhone'] as String? ?? '',
  gymTimings: map['gymTimings'] as String? ?? '',
  isTaxEnabled: map['isTaxEnabled'] as bool? ?? false,
  taxLabel: map['taxLabel'] as String? ?? 'GST',
  taxRatePercent: (map['taxRatePercent'] as num?)?.toDouble() ?? 18.0,
  isTaxInclusive: map['isTaxInclusive'] as bool? ?? true,
  receiptTerms: map['receiptTerms'] as String? ?? 'All gym membership fees once paid are non-refundable...',
  ```
  Empty-string defaults for address/phone/timings prevent `null` crashes while keeping the receipt clean (empty values should hide their sections).

### Step 2: Add Settings Configuration UI
- In `EditProfileScreen` / `SettingsTab`:
  - Add collapsible or dedicated sections:
    - **Gym Details**: Name, Tagline, Address, Phone, Timings.
    - **Receipt & Tax Preferences**:
      - Switch: `Enable Tax / GST on Receipts`.
      - If enabled: Tax Label and Tax Rate %.
      - Text field: `Terms & Conditions (Footer Note)`.

### Step 3: Update PDF Receipt Service
- In `PaymentReceiptPdfService`:
  - Fetch `gymSettings = GymService().settings`.
  - Print `gymSettings.gymAddress` and `gymPhone` beneath the gym title in the receipt header.
  - In the financial summary breakdown:
    - If `gymSettings.isTaxEnabled`: compute tax amount and display `"${gymSettings.taxLabel} (${gymSettings.taxRatePercent}%)"`.
    - If not enabled: hide the tax row completely.
  - In the Terms & Conditions container:
    - Replace the hardcoded 4 strings with `gymSettings.receiptTerms`.

### Step 4: Update Splash Screen & WhatsApp Service
- In `SplashScreen` (line 172):
  - **Timing caveat**: The splash screen renders *before* `GymService` is fully initialized (it's the first screen shown while data loads). `GymService().settings.gymName` will return the hardcoded default `'IronPulse Fitness Club'` until SharedPreferences loads.
  - Solutions (pick one):
    - Use `SharedPreferences.getInstance()` directly in the splash to read just the gym name synchronously.
    - Use a `FutureBuilder` / `ListenableBuilder` that updates the text once `GymService` finishes initialization.
    - Accept the brief default display during the 1-2 second splash animation.
  - Read `settings.gymTagline` for the subtitle (currently hardcoded as `'GYM MANAGEMENT & BILLING SUITE'` at line 185).
- In `WhatsAppService` (line 290):
  - Read `settings.gymTimings` instead of hardcoded morning/evening constants.

---

## 5. Edge Cases & Considerations
- **Default Upgrades**: Existing installations upgrading their settings must retain valid sensible defaults so receipts don't have blank terms or missing names.
- **Multilingual / Custom Characters**: Ensure receipt terms support multiline text with line breaks cleanly rendered inside the PDF layout without overflow.
- **Empty Address / Phone**: If the owner has not provided an address or phone number, hide those header lines gracefully rather than printing blank spaces.

---

## 6. Validation & Testing Checklist
- [ ] Change Gym Name to "Titan Fitness" in Settings: verify Splash screen displays "Titan Fitness".
- [ ] Turn off Tax / GST in Settings: generate a receipt PDF and verify no GST line appears.
- [ ] Turn on Tax (18% GST): verify the receipt calculates and displays the tax line properly.
- [ ] Customize gym timings in Settings: preview a WhatsApp welcome message and verify the custom timings appear.
- [ ] Edit receipt terms: verify the updated terms are rendered on the printed PDF.
