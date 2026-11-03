"""Crop white square-margin from the OPTACA tourism seal; keep the circle."""
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

src = Path(
    r"c:\tripplanner2.0\linontripplanner-main\assets\images"
    r"\Misamis Occidental Tourism Seal.png"
)
dst = Path(
    r"c:\tripplanner2.0\linontripplanner-main\assets\images"
    r"\misamis_occidental_tourism_seal_sidebar.png"
)

im = Image.open(src).convert("RGB")
arr = np.asarray(im)
h, w = arr.shape[:2]
luma = arr.mean(axis=2)
spread = arr.max(axis=2) - arr.min(axis=2)
# Near-white, low-chroma pixels (the square paper background), not the
# cyan outer ring of the seal.
margin = (luma >= 247) & (spread <= 18)

visited = np.zeros((h, w), dtype=bool)
q = deque()
for x in range(w):
    for y in (0, h - 1):
        if margin[y, x]:
            visited[y, x] = True
            q.append((x, y))
for y in range(h):
    for x in (0, w - 1):
        if margin[y, x] and not visited[y, x]:
            visited[y, x] = True
            q.append((x, y))

while q:
    x, y = q.popleft()
    for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
        if 0 <= nx < w and 0 <= ny < h and margin[ny, nx] and not visited[ny, nx]:
            visited[ny, nx] = True
            q.append((nx, ny))

rgba = np.dstack([arr, np.full((h, w), 255, dtype=np.uint8)])
rgba[visited, 3] = 0

ys, xs = np.where(rgba[:, :, 3] > 0)
x0, x1 = int(xs.min()), int(xs.max())
y0, y1 = int(ys.min()), int(ys.max())
# Tight square around the opaque seal — no extra pad (that reintroduces
# the white-looking gap inside the orange sidebar tile).
side = max(x1 - x0 + 1, y1 - y0 + 1)
cx = (x0 + x1) / 2
cy = (y0 + y1) / 2
left = int(round(cx - side / 2))
top = int(round(cy - side / 2))
left = max(0, min(left, w - side))
top = max(0, min(top, h - side))
cropped = rgba[top : top + side, left : left + side]

out = Image.fromarray(cropped, "RGBA")
# 512px is sharp at 44 logical pixels on high-DPI Windows without the 2MB original.
out = out.resize((512, 512), Image.Resampling.LANCZOS)
out.save(dst, "PNG", optimize=True)
print(
    f"src={w}x{h} crop=({left},{top},{side}) "
    f"opaque=({x0},{y0})-({x1},{y1}) out={dst.name} "
    f"{dst.stat().st_size} bytes"
)
