# TASK-03: Fast Member Search across Attendance, Billing, and Card Numbers

## Priority: High
## Category: Daily Operational Efficiency

---

## 1. Problem Statement
The two screens gym owners use multiple times every single day are:
1. **Daily Attendance Tab**: Members walk in, give their name or card number, and get checked in.
2. **Billing / Collections Tab**: Members walk up to pay fees or settle dues.

Currently:
- In [gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L785-L791), `searchCustomers()` only checks `c.name` and `c.phone`. It completely ignores `c.cardNumber`.
- In [daily_attendance_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/attendance/daily_attendance_tab.dart#L1), there is **no search bar**. The owner must manually scroll through the entire membership list to find a member.
- In [billing_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/billing/billing_tab.dart#L1), there is also **no search bar**. Finding a member to collect balance requires endless scrolling.

In a facility with 100+ active members, the absence of search renders check-ins and payments tedious and slow.

---

## 2. Goals & Objectives
1. **Search by Card Number Everywhere**:
   - Enhance the global search query to match `cardNumber` in addition to `name` and `phone`.
2. **Instant Search in Daily Attendance**:
   - Provide a persistent or quick-toggle search bar at the top of the daily attendance screen.
   - Filter the list in real-time as the owner types.
3. **Instant Search in Billing & Collections**:
   - Provide a search bar in the Collections view that seamlessly combines with the existing `All`, `Pending`, and `Paid` filter tabs.
4. **Fast Keyboard Dismissal & Clear**:
   - Include a clear (`X`) button and smooth autofocus/unfocus behavior.

---

## 3. Impacted Files
- [lib/services/gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L785-L791)
- [lib/screens/attendance/daily_attendance_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/attendance/daily_attendance_tab.dart#L80-L150)
- [lib/screens/billing/billing_tab.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/screens/billing/billing_tab.dart#L80-L160)

---

## 4. Detailed Implementation Steps

### Step 1: Upgrade `GymService.searchCustomers()`
- Update [gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L785):
  ```dart
  List<Customer> searchCustomers(String query) {
    if (query.trim().isEmpty) return customers;
    final q = query.toLowerCase().trim();
    return _customers.where((c) {
      final nameMatch = c.name.toLowerCase().contains(q);
      final phoneMatch = c.phone.contains(q);
      final cardMatch = c.cardNumber.toLowerCase().contains(q);
      return nameMatch || phoneMatch || cardMatch;
    }).toList();
  }
  ```

### Step 2: Implement Search in `DailyAttendanceTab`
- Add `TextEditingController _searchController` and `String _searchQuery = ''` to `_DailyAttendanceTabState`.
- Add a modern search field below the date picker or in the AppBar:
  - Icon prefix: `Icons.search_rounded`.
  - Hint: `"Search by name, phone, or card #..."`.
  - Suffix icon: Clear (`Icons.close_rounded`) when `_searchQuery.isNotEmpty`.
- Apply search filtering to `activeCustomers`:
  ```dart
  final filtered = activeCustomers.where((c) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    return c.name.toLowerCase().contains(q) ||
           c.phone.contains(q) ||
           c.cardNumber.toLowerCase().contains(q);
  }).toList();
  ```
- Add an empty state UI when `filtered.isEmpty && _searchQuery.isNotEmpty`:
  *"No members found matching '[query]'"*.

### Step 3: Implement Search in `BillingTab`
- Add search state to `_BillingTabState`.
- Position the search bar **above the existing `ChoiceChip`-style filter buttons** (`All`, `Pending`, `Paid`) which are custom `InkWell`/chip widgets. The filters are NOT Flutter `SegmentedButton` — they are styled chips at approximately lines 108-125 inside a `SingleChildScrollView`. Place the search field above this scrollable chip row.
- Ensure search query filters the already-categorized customer list (the `customers` variable at line 80, after the existing `_filter` logic has been applied).

---

## 5. Edge Cases & Considerations
- **Partial Card Numbers**: Typing `"12"` should match Card `#12`, Card `#112`, and Card `#120`.
- **Keyboard Overlap on Small Screens**: Ensure search bar is integrated inside the scrollable view or pinned in an `SliverAppBar` so the keyboard does not cause overflow errors on 320px/360px screens.
- **Performance**: Instant in-memory filtering for up to 2,000 members is instantaneous (<1ms) and requires no asynchronous debounce.

---

## 6. Validation & Testing Checklist
- [ ] In Members tab: search for an existing card number (e.g. `105`) and verify the member appears.
- [ ] In Daily Attendance tab: type a member's card number and verify only their card remains visible.
- [ ] Mark attendance from the filtered search result: confirm attendance toggles properly without losing search state.
- [ ] In Billing tab: select "Pending" filter, then search by name: verify only pending members matching the name appear.
- [ ] Tap the clear (`X`) button in both screens and verify full list is restored.
