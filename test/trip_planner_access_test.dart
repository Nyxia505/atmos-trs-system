import 'package:atmos_trs_system/navigation/login_route_args.dart';
import 'package:atmos_trs_system/navigation/trip_planner_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('itinerary login args force tourist-only signup', () {
    final args = LoginRouteArgs.from(
      LoginRouteArgs.forFeature(returnFeature: LoginRouteArgs.featureItinerary),
    );
    expect(args?.touristOnlySignup, isTrue);
    expect(args?.loginOnly, isTrue);
    expect(args?.returnFeature, LoginRouteArgs.featureItinerary);
  });

  test('QR login is tourist-only and keeps ATMOS branding', () {
    final args = LoginRouteArgs.from(
      LoginRouteArgs.forFeature(returnFeature: LoginRouteArgs.featureQr),
    );
    expect(args?.touristOnlySignup, isTrue);
    expect(args?.usesTripPlannerBranding, isFalse);
  });

  test('Trip Planner login uses Trip Planner branding', () {
    final args = LoginRouteArgs.from(
      LoginRouteArgs.forFeature(
        returnFeature: LoginRouteArgs.featureItinerary,
      ),
    );
    expect(args?.usesTripPlannerBranding, isTrue);
    expect(args?.touristOnlySignup, isTrue);
  });

  test('VR login args keep the account-type signup chooser', () {
    final args = LoginRouteArgs.from(
      LoginRouteArgs.forFeature(returnFeature: LoginRouteArgs.featureVr),
    );
    expect(args?.touristOnlySignup, isFalse);
  });

  test('only the tourist role may open Trip Planner', () {
    expect(TripPlannerAccess.allowsRole('tourist'), isTrue);
    expect(TripPlannerAccess.allowsRole('Tourist'), isTrue);
    expect(TripPlannerAccess.allowsRole('tourism_establishment'), isFalse);
    expect(TripPlannerAccess.allowsRole('tourism_office'), isFalse);
    expect(TripPlannerAccess.allowsRole('tourism'), isFalse);
    expect(TripPlannerAccess.allowsRole('governor'), isFalse);
    expect(TripPlannerAccess.allowsRole(null), isFalse);
  });
}
