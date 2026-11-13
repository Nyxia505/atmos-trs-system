"""Build tourist-signup address assets from the PSGC mirror.

Misamis Occidental is omitted. Signup keeps the existing Dart city and
barangay lists for that province.

Source: https://psgc.gitlab.io/api/
Expects %TEMP%/psgc/provinces.json, cities.json, and barangays.json.
"""

from __future__ import annotations

import json
import os
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = Path(os.environ.get("TEMP", "/tmp")) / "psgc"
OUT = ROOT / "assets" / "ph_address"
MISOCC = "104200000"
BASILAN = "150700000"
MAGUINDANAO = "153800000"
ISABELA_CITY = "099701000"
COTABATO_CITY = "129804000"
NCR = "130000000"
SMALL = {"del", "de", "of", "and", "the"}


def display_name(raw: str) -> str:
    name = raw.strip()
    if name.startswith("City of "):
        name = f"{name[len('City of '):]} City"
    parts = []
    for index, part in enumerate(name.split(" ")):
        if index > 0 and part.lower() in SMALL:
            parts.append(part.lower())
        else:
            parts.append(part)
    return " ".join(parts)


def slugify(name: str) -> str:
    text = name.lower()
    text = text.replace("ñ", "n")
    text = re.sub(r"[^a-z0-9]+", "-", text)
    return text.strip("-")


def main() -> None:
    provinces = json.loads((SRC / "provinces.json").read_text(encoding="utf-8"))
    cities = json.loads((SRC / "cities.json").read_text(encoding="utf-8"))
    barangays = json.loads((SRC / "barangays.json").read_text(encoding="utf-8"))

    code_to_name = {
        item["code"]: display_name(item["name"])
        for item in provinces
        if item["code"] != MISOCC
    }
    code_to_name["metro-manila"] = "Metro Manila"

    def province_for(city: dict) -> str | None:
        code = city.get("provinceCode")
        if isinstance(code, str) and code:
            if code == MISOCC:
                return None
            return code_to_name.get(code)
        if city["code"] == ISABELA_CITY:
            return code_to_name[BASILAN]
        if city["code"] == COTABATO_CITY:
            return code_to_name[MAGUINDANAO]
        if city.get("regionCode") == NCR:
            return "Metro Manila"
        return None

    city_code_to_place: dict[str, tuple[str, str]] = {}
    cities_by_province: dict[str, list[str]] = defaultdict(list)
    for city in cities:
        province = province_for(city)
        if province is None:
            continue
        label = display_name(city["name"])
        city_code_to_place[city["code"]] = (province, label)
        cities_by_province[province].append(label)

    for names in cities_by_province.values():
        names.sort(key=str.lower)

    barangays_by_place: dict[tuple[str, str], list[str]] = defaultdict(list)
    unmatched = 0
    for row in barangays:
        parent = row.get("municipalityCode") or row.get("cityCode")
        if not isinstance(parent, str) or not parent:
            unmatched += 1
            continue
        place = city_code_to_place.get(parent)
        if place is None:
            if row.get("provinceCode") == MISOCC:
                continue
            unmatched += 1
            continue
        barangays_by_place[place].append(row["name"])

    for names in barangays_by_place.values():
        names.sort(key=str.lower)

    records = []
    for name in sorted(cities_by_province, key=str.lower):
        records.append(
            {
                "name": name,
                "slug": slugify(name),
                "cities": cities_by_province[name],
            }
        )

    barangay_dir = OUT / "barangays"
    barangay_dir.mkdir(parents=True, exist_ok=True)
    for old in barangay_dir.glob("*.json"):
        old.unlink()

    (OUT / "cities_by_province.json").write_text(
        json.dumps(records, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    empty_cities = 0
    for record in records:
        payload = {}
        for city in record["cities"]:
            names = barangays_by_place.get((record["name"], city), [])
            payload[city] = names
            if not names:
                empty_cities += 1
        (barangay_dir / f"{record['slug']}.json").write_text(
            json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )

    print(
        f"provinces={len(records)} cities={sum(len(r['cities']) for r in records)} "
        f"barangays={sum(len(v) for v in barangays_by_place.values())} "
        f"unmatched={unmatched} empty_city_lists={empty_cities}"
    )


if __name__ == "__main__":
    main()
