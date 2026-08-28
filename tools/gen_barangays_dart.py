import re
from pathlib import Path

text = Path(
    r"C:\Users\sapin\.cursor\projects\c-atmos-trs-system\agent-tools\b19a6266-66c5-4c38-9640-3244311d9c23.txt"
).read_text(encoding="utf-8")
pat = re.compile(r"\[([^\]]+)\]\([^)]+\),\s*([A-Za-z0-9 .\-]+)")
muni_map: dict[str, set[str]] = {}
for name, muni in pat.findall(text):
    name = name.strip()
    muni = muni.strip()
    if name:
        muni_map.setdefault(muni, set()).add(name)

signup_labels = {
    "Aloran": "Aloran",
    "Baliangao": "Baliangao",
    "Bonifacio": "Bonifacio",
    "Calamba": "Calamba",
    "Clarin": "Clarin",
    "Concepcion": "Concepcion",
    "Don Victoriano Chiongbian": "Don Victoriano Chiongbian",
    "Jimenez": "Jimenez",
    "Lopez Jaena": "Lopez Jaena",
    "Oroquieta": "Oroquieta City",
    "Ozamiz": "Ozamiz City",
    "Panaon": "Panaon",
    "Plaridel": "Plaridel",
    "Sapang Dalaga": "Sapang Dalaga",
    "Sinacaban": "Sinacaban",
    "Tangub": "Tangub City",
    "Tudela": "Tudela",
}

out: dict[str, list[str]] = {}
for muni, names in muni_map.items():
    key = signup_labels.get(muni)
    if key:
        out[key] = sorted(names)

lines = [
    "// Barangays per city/municipality in Misamis Occidental (PhilAtlas 2020).",
    "// Used by signup address dropdown.",
    "",
    "const Map<String, List<String>> kMisamisOccidentalBarangaysByCity = {",
]
for city in sorted(out.keys()):
    lines.append(f"  '{city}': [")
    for b in out[city]:
        esc = b.replace("'", "\\'")
        lines.append(f"    '{esc}',")
    lines.append("  ],")
lines += [
    "};",
    "",
    "List<String> barangaysForMisamisOccidentalCity(String? city) {",
    "  if (city == null || city.trim().isEmpty) return const [];",
    "  return List<String>.from(",
    "    kMisamisOccidentalBarangaysByCity[city] ?? const [],",
    "  );",
    "}",
    "",
    "bool isMisamisOccidentalSignupCity(String? city) {",
    "  if (city == null) return false;",
    "  return kMisamisOccidentalBarangaysByCity.containsKey(city);",
    "}",
    "",
]

out_path = Path(__file__).resolve().parents[1] / "lib" / "data" / "misamis_occidental_barangays.dart"
out_path.write_text("\n".join(lines), encoding="utf-8")
print(f"wrote {out_path} ({sum(len(v) for v in out.values())} barangays)")
