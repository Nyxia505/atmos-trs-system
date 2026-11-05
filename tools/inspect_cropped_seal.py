from PIL import Image
import numpy as np

p = r"c:\tripplanner2.0\linontripplanner-main\assets\images\misamis_occidental_tourism_seal_sidebar.png"
im = Image.open(p)
arr = np.asarray(im)
print("mode", im.mode, "size", im.size)
a = arr[:, :, 3]
print("alpha min/max", int(a.min()), int(a.max()), "transparent%", float((a == 0).mean()) * 100)
print("corners alpha", a[0, 0], a[0, -1], a[-1, 0], a[-1, -1])
print("center alpha", a[256, 256], "center rgb", arr[256, 256, :3].tolist())
ys, xs = np.where(a > 8)
print("opaque bbox", int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()),
      "frac", (xs.max()-xs.min()+1)/arr.shape[1])
