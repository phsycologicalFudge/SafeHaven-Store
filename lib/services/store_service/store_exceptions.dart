class StoreApiException implements Exception {
  const StoreApiException(this.message);

  final String message;

  @override
  String toString() => message;
}