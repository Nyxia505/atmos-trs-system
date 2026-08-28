"""One-off: remove inner BoxDecoration borders from tourism_dashboard.dart only."""
import re
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "lib" / "screens" / "tourism_dashboard.dart"
text = path.read_text(encoding="utf-8")

must_keep = [
    "border: Border.all(color: _primaryOrange, width: 25)",
    "border: Border.all(color: _primaryOrange, width: 2)",
]
for m in must_keep:
    if m not in text:
        raise SystemExit(f"missing preserved fragment: {m}")

# Remove whole lines that are only a BoxDecoration border (not OutlineInputBorder).
line_patterns = [
    r"^[ \t]*border: Border\.all\(color: const Color\(0xFFE5E7EB\), width: 1\),\s*\r?\n",
    r"^[ \t]*border: Border\.all\(color: Colors\.grey\.shade200\),\s*\r?\n",
    r"^[ \t]*border: Border\.all\(color: Colors\.grey\.shade300\),\s*\r?\n",
    r"^[ \t]*border: Border\.all\(color: _cardBorder\),\s*\r?\n",
    r"^[ \t]*border: Border\.all\(color: _cardBorder, width: 1\.5\),\s*\r?\n",
    r"^[ \t]*border: Border\.bottom\(BorderSide\(color: Colors\.grey\.shade300\)\),\s*\r?\n",
    r"^[ \t]*border: Border\(top: BorderSide\(color: Colors\.grey\.shade200\)\),\s*\r?\n",
    r"^[ \t]*border: Border\(left: BorderSide\(color: _primaryOrange, width: 4\)\),\s*\r?\n",
    r"^[ \t]*border: Border\(\s*left: BorderSide\(color: _primaryOrange, width: 3\),\s*\),\s*\r?\n",
    r"^[ \t]*border: Border\.all\(\s*color: const Color\(0xFFD4D4D4\),\s*\),\s*\r?\n",
    r"^[ \t]*border: Border\(top: BorderSide\(color: _cardBorder\)\),\s*\r?\n",
    r"^[ \t]*border: Border\.all\(color: _primaryOrange, width: 1\.5\),\s*\r?\n",
    r"^[ \t]*border: Border\.all\(color: borderColor, width: 2\),\s*\r?\n",
    r"^[ \t]*border: Border\.all\(color: _cardBg, width: 3\),\s*\r?\n",
]
for pat in line_patterns:
    text = re.sub(pat, "", text, flags=re.MULTILINE)

# Profile chip (multi-line Border.all)
text = re.sub(
    r"[ \t]*border: Border\.all\(\s*\n[ \t]*color: _primaryOrange\.withOpacity\(0\.25\),\s*\n[ \t]*width: 1\.5,\s*\n[ \t]*\),\s*\n",
    "",
    text,
)

# Status badge inner border
text = re.sub(
    r"[ \t]*border: Border\.all\(\s*\n[ \t]*color: \(isVerified \? _primaryOrange : Colors\.orange\)\.withOpacity\(0\.4\),\s*\n[ \t]*width: 1,\s*\n[ \t]*\),\s*\n",
    "",
    text,
)

# DataTable inner grid lines (tourist export)
text = text.replace(
    """border: TableBorder.symmetric(
                                inside: BorderSide(
                                  color: _cardBorder.withValues(alpha: 0.8),
                                ),
                              ),""",
    "border: const TableBorder(),",
)

for m in must_keep:
    if m not in text:
        raise SystemExit(f"lost preserved fragment after edit: {m}")

path.write_text(text, encoding="utf-8")
print("Updated", path)
