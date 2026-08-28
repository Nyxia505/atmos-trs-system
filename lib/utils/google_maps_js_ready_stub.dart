/// Non-web: Google Maps native SDK is always available.
bool isGoogleMapsJsReady() => true;

/// Non-web: auth failures are surfaced by the native SDK, not `gm_authFailure`.
bool isGoogleMapsAuthFailed() => false;
