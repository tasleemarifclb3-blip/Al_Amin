/// Rules for the "database generation" (reset epoch).
///
/// Every global reset gets a unique token, stored in Firebase and on each
/// device. Every change a device uploads is stamped with the token its device
/// holds. A device only accepts changes of its own generation, so old data that
/// is uploaded late by a device that had not yet seen the reset can never bring
/// deleted records back.
class ResetEpoch {
  ResetEpoch._();

  /// True when a cloud change belongs to the generation this device is on.
  ///
  /// * A change stamped with the device's token is current.
  /// * A device that has never seen a reset (empty token) accepts untagged changes.
  /// * Changes written by an older app version carry no token. They are accepted
  ///   only if they were created at or after the moment the current reset was
  ///   published ([epochStart]); anything older belongs to the deleted database.
  static bool isCurrent(
    Object? changeToken,
    String deviceToken, {
    DateTime? changeCreatedAt,
    DateTime? epochStart,
  }) {
    final token = (changeToken ?? '').toString();
    if (token.isNotEmpty) return token == deviceToken;
    if (deviceToken.isEmpty) return true;
    if (changeCreatedAt == null || epochStart == null) return false;
    return !changeCreatedAt.isBefore(epochStart);
  }

  /// True when Firebase holds a reset this device has not applied yet.
  static bool resetPending({required String remoteToken, required String appliedToken}) =>
      remoteToken.isNotEmpty && remoteToken != appliedToken;

  /// Two devices may exchange data directly only if they are on the same generation.
  static bool sameGeneration(String a, String b) => a == b;
}
