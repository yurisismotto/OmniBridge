import numpy as np
from PIL import Image
from skimage import filters, segmentation, color, morphology

im = np.array(Image.open('ref-mark.png')).astype(float) / 255
a = im[..., 3]
rgb = im[..., :3]
sil = a > 0.5
sil = morphology.remove_small_objects(sil, 2000)
lab = color.rgb2lab(rgb)
g = np.zeros(a.shape)
for c in range(3):
    g += filters.sobel(filters.gaussian(lab[..., c], 1.5)) ** 2
g = np.sqrt(g)
np.save('grad.npy', g)
seeds = {
    'A': [(500, 250), (150, 600), (1100, 500), (700, 300), (1150, 650)],
    'B': [(270, 780), (300, 830)],
    'D': [(650, 650), (980, 560), (450, 850), (320, 1050), (800, 700)],
    'E': [(850, 1000), (600, 930), (950, 1100)],
}
markers = np.zeros(a.shape, int)
names = list(seeds)
for i, k in enumerate(names):
    for (x, y) in seeds[k]:
        markers[y - 4:y + 5, x - 4:x + 5] = i + 1
markers[~sil] = 0
bg = len(names) + 1
markers[a < 0.1] = bg
lbl = segmentation.watershed(g, markers)
lbl[~sil] = 0
lbl[lbl == bg] = 0
np.save('lbl.npy', lbl)
np.save('sil.npy', sil)
pal = np.array([[255, 255, 255], [24, 184, 201], [20, 30, 120], [79, 107, 255], [124, 92, 252]], np.uint8)
Image.fromarray(pal[lbl]).save('seg.png')
b = segmentation.find_boundaries(lbl)
ov = ((rgb * a[..., None] + (1 - a[..., None])) * 255).astype(np.uint8)
ov[b] = [255, 0, 0]
Image.fromarray(ov).save('seg-overlay.png')
for i, k in enumerate(names):
    print(k, (lbl == i + 1).sum())
