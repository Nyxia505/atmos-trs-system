"""Inspect Misamis Occidental Tourism Seal margins."""
from PIL import Image
import numpy as np

path = r"c:\tripplanner2.0\linontripplanner-main\assets\images\Misamis Occidental Tourism Seal.png"
im = Image.open(path).convert("RGB")
arr = np.asarray(im)
print("size", arr.shape)
# Distance from white
diff = 255 - arr.min(axis=2)
# Also luma
luma = arr.mean(axis=2)

def bbox_for(mask):
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())

print("corner RGB", arr[0, 0].tolist(), arr[0, -1].tolist(), arr[-1, 0].tolist())
print("center RGB", arr[arr.shape[0] // 2, arr.shape[1] // 2].tolist())

for name, mask in [
    ("not_pure_white", np.any(arr < 255, axis=2)),
    ("luma<250", luma < 250),
    ("luma<245", luma < 245),
    ("luma<240", luma < 240),
    ("luma<230", luma < 230),
    ("luma<220", luma < 220),
    ("max_channel_drop>8", (255 - arr.max(axis=2)) > 8),
    ("any_channel_drop>12", (255 - arr.min(axis=2)) > 12),
]:
    b = bbox_for(mask)
    if b is None:
        print(name, "empty")
        continue
    x0, y0, x1, y1 = b
    print(
        f"{name:22} bbox=({x0},{y0})-({x1},{y1}) "
        f"w={x1-x0+1} h={y1-y0+1} "
        f"left={x0} top={y0} right={arr.shape[1]-1-x1} bottom={arr.shape[0]-1-y1} "
        f"frac={(x1-x0+1)/arr.shape[1]:.3f}"
    )

# Sample a horizontal midline from left edge until non-white
mid = arr.shape[0] // 2
row = luma[mid]
for i, v in enumerate(row):
    if v < 250:
        print("midline first luma<250 at x", i, "rgb", arr[mid, i].tolist())
        break
for i, v in enumerate(row[::-1]):
    if v < 250:
        print("midline last luma<250 at x", arr.shape[1] - 1 - i, "rgb", arr[mid, arr.shape[1] - 1 - i].tolist())
        break
