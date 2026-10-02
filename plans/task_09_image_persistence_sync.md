# TASK-09: Permanent Media Storage & Cross-Device Sync

## Priority: Medium
## Category: Media Reliability & Multi-Device Synchronization

---

## 1. Problem Statement
Handling of member profile photos and gym logos currently has two points of failure:
- **Temporary Cache Paths**: In [avatar_selector.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/widgets/avatar_selector.dart#L56), the path returned by `image_picker` (e.g. `/cache/image_picker_xxx.jpg`) is saved directly to `customer.imagePath` and `settings.gymLogoPath`. Operating systems (Android/iOS) routinely clean up application cache directories, causing photos to disappear or show broken image placeholders after a few days.
- **Cross-Device Path Failure**: When syncing a customer to Firestore, only the local file path string (e.g. `/data/user/0/com.example.gym/cache/...`) is sent to the cloud. When the gym owner logs in on a second device (or web/tablet), that local file path does not exist on the other device, resulting in failed image loads.

---

## 2. Goals & Objectives
1. **Permanent Local Directory Storage**:
   - Immediately copy selected photos from the temporary cache directory into the application's permanent documents directory (`/app_flutter/member_photos/`).
   - Store stable filenames keyed by member ID or timestamp (`avatar_${customerId}.jpg`).
2. **Cross-Device Avatar Synchronization**:
   - Enable avatars to display reliably across different devices:
     - Store a compressed, optimized thumbnail (100×100 px, ~6–10 KB JPEG Base64) in the customer model/Firestore document for fast, lightweight cross-device sync without requiring separate cloud storage buckets.
     - On local devices, read the cached high-resolution file if present, falling back smoothly to the synced base64 thumbnail.
3. **Gym Logo Persistence**:
   - Store the gym's official logo permanently in app documents and synchronize it across devices.

---

## 3. Required New Dependencies (not currently in `pubspec.yaml`)
- **`path_provider`**: For `getApplicationDocumentsDirectory()` to access the persistent documents directory. Not currently in pubspec.yaml. (Shared with Task 07 and Task 08.)

---

## 4. Impacted Files
- [lib/widgets/avatar_selector.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/widgets/avatar_selector.dart#L46-L70)
- [lib/models/customer.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/models/customer.dart#L43)
- [lib/services/gym_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/gym_service.dart#L510-L550)
- [lib/services/firestore_service.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/services/firestore_service.dart#L235-L245)
- [lib/widgets/customer_avatar.dart](file:///d:/Flutter%20Projects/gym/GymManagement2/GymManagement/lib/widgets/customer_avatar.dart#L1-L60)

---

## 5. Detailed Implementation Steps

### Step 1: Implement Image File Persistence Utility
- In a helper service (e.g. `lib/utils/image_storage_utils.dart`):
  ```dart
  class ImageStorageUtils {
    static Future<String> persistImage(String tempPath, String fileName) async {
      final docDir = await getApplicationDocumentsDirectory();
      final targetFolder = Directory('${docDir.path}/media');
      if (!await targetFolder.exists()) {
        await targetFolder.create(recursive: true);
      }
      final targetPath = '${targetFolder.path}/$fileName';
      final file = File(tempPath);
      final savedFile = await file.copy(targetPath);
      return savedFile.path;
    }

    static Future<String?> createThumbnailBase64(String filePath) async {
      // Compresses image to 100x100 and returns base64 string
    }
  }
  ```

### Step 2: Update `AvatarSelector`
- When image is picked:
  - Copy to persistent storage directory.
  - Return the persistent file path.

### Step 3: Update `Customer` Model for Cross-Device Thumbnails
- Add a new field to `Customer` (line 43 area):
  ```dart
  final String? imageBase64; // Compressed 100x100 thumbnail for cross-device sync
  ```
- Update `copyWith()` to include `imageBase64`.
- Update `toMap()`: `'imageBase64': imageBase64,`
- Update `fromMap()`: `imageBase64: map['imageBase64'] as String?,`
- **Migration safety**: Existing stored records won't have this field, so `fromMap()` must default to `null` (existing user records load cleanly without thumbnails until their next photo update).

### Step 4: Update `CustomerAvatar` Widget
- In `CustomerAvatar` (line 44 already handles `avatar:` prefix types):
  - After the existing avatar-type check, add a block for file-based images:
    - Check if `customer.imagePath` is a valid existing local file (using `File(path).existsSync()`).
    - If file does not exist locally (e.g. on second phone), check for `customer.imageBase64` and render `Image.memory(base64Decode(customer.imageBase64!))`.
    - Fall back cleanly to gradient/icon avatar if neither is present.

---

## 6. Edge Cases & Considerations
- **Storage Cleanup**: When updating a member's photo or permanently deleting a member, delete the old image file from the persistent directory to avoid disk clutter.
- **Large Photos**: Camera photos can be 5–12 MB. Always compress to max 800×800 px before saving locally, and 100×100 px for the base64 sync thumbnail.

---

## 7. Validation & Testing Checklist
- [ ] Select a profile photo for a member, then clear app cache via Android settings: verify photo continues to display properly.
- [ ] Inspect file path: confirm image is saved in persistent app documents rather than temporary cache.
- [ ] Simulate second device by removing local file: verify the fallback base64 thumbnail renders smoothly.
- [ ] Select a custom gym logo in Settings: verify it persists across app restarts and is rendered in printed receipts.
