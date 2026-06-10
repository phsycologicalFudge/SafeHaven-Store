import 'dart:developer';
import '../device_identity_service.dart';
import '../store_service.dart';

enum RatingResult { ok, alreadyRated, rateLimited, notFound, error }

class RatingService {
  RatingService._();
  static final RatingService instance = RatingService._();

  Future<RatingResult> submitRating({
    required String packageName,
    required int rating,
  }) async {
    final token = await DeviceIdentityService.instance.getToken();
    if (token == null) {
      log('token_missing');
      return RatingResult.error;
    }

    try {
      await StoreService.instance.submitRating(
        packageName: packageName,
        deviceToken: token,
        rating: rating,
      );
      return RatingResult.ok;
    } on StoreApiException catch (e) {
      log(e.message);
      switch (e.message) {
        case 'already_rated':
          return RatingResult.alreadyRated;
        case 'rate_limited':
          return RatingResult.rateLimited;
        case 'not_found':
        case 'app_not_found':
          return RatingResult.notFound;
        default:
          return RatingResult.error;
      }
    } catch (e) {
      log(e.toString());
      return RatingResult.error;
    }
  }
}
