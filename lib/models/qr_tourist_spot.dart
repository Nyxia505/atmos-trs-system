class QrTouristSpot {
  final String id; // e.g. SPOT001
  final String name;
  final String municipality;
  final String qrCodeValue; // payload encoded in the QR
  final String deepLink; // e.g. https://myapp.com/checkin?spot_id=SPOT001
  final String image;
  final String description;

  const QrTouristSpot({
    required this.id,
    required this.name,
    required this.municipality,
    required this.qrCodeValue,
    required this.deepLink,
    required this.image,
    required this.description,
  });
}

