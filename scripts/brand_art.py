"""Render the store art into assets/brand/: python -m scripts.brand_art.

The thumbnail's network is the real one: a drawn 7 goes through the reference preprocessing and the
exported int8 weights, and the links follow the Explain rules. Needs training/out/model.pt and macOS fonts.
"""

from pathlib import Path

import numpy as np
import torch
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

from training import config
from training.export import Layer, forward_all, model_version, quantize_layers
from training.preprocess import preprocess

OUT_DIR = config.REPO_ROOT / "assets" / "brand"
AVENIR = Path("/System/Library/Fonts/Avenir Next.ttc")

Color = tuple[int, int, int]
Point = tuple[float, float]

# The game's palette, from Config.luau.
POSITIVE: Color = (70, 180, 255)
NEGATIVE: Color = (255, 140, 40)
ORB_DIM: Color = (30, 60, 110)
ORB_BRIGHT: Color = (120, 215, 255)
INK: Color = (235, 245, 255)
PIXEL_OFF: Color = (16, 20, 30)
MUTED: Color = (130, 145, 170)
BAR_BACK: Color = (38, 46, 64)
BAR: Color = (90, 170, 255)
WINNER_BAR: Color = (190, 240, 255)
TABLET: Color = (24, 26, 32)
TABLET_STROKE: Color = (88, 94, 108)
SURFACE: Color = (14, 18, 28)

# A hand-drawn 7 in pad space, 0..1.
SEVEN: list[Point] = [
    (0.14, 0.17), (0.28, 0.15), (0.46, 0.13), (0.64, 0.115), (0.84, 0.10), (0.80, 0.21),
    (0.72, 0.36), (0.63, 0.50), (0.54, 0.65), (0.47, 0.79), (0.43, 0.91),
]  # fmt: skip

SS = 2  # supersampling


def font(size: float, style: str = "Heavy") -> ImageFont.FreeTypeFont:
    for index in range(16):
        candidate = ImageFont.truetype(str(AVENIR), max(1, round(size)), index=index)
        if candidate.getname()[1] == style:
            return candidate
    raise RuntimeError(f"Avenir Next has no {style} style")


def scaled(color: Color, amount: float) -> Color:
    return (round(color[0] * amount), round(color[1] * amount), round(color[2] * amount))


def mix(a: Color, b: Color, t: float) -> Color:
    return (round(a[0] + (b[0] - a[0]) * t), round(a[1] + (b[1] - a[1]) * t), round(a[2] + (b[2] - a[2]) * t))


def load_layers() -> list[Layer]:
    state = torch.load(config.CHECKPOINT_PATH, map_location="cpu", weights_only=True)["state_dict"]
    return quantize_layers(state)


def top_pairs(values: np.ndarray, count: int) -> list[tuple[int, int]]:
    order = np.argsort(-np.abs(values), axis=None, kind="stable")[:count]
    return [(int(i), int(j)) for i, j in zip(*np.unravel_index(order, values.shape))]


def select_edges(layers: list[Layer], image: np.ndarray, acts: list[np.ndarray], predicted: int):
    """The links Explain.luau would show: (layer, src, dst, value / layer max)."""
    edges: list[tuple[int, int, int, float]] = []

    contributions: list[tuple[int, int, float]] = []
    for neuron in np.argsort(-acts[0], kind="stable")[:16]:
        values = image * layers[0].weights[:, neuron]
        for pixel in np.argsort(-values, kind="stable")[:6]:
            if values[pixel] > 0:
                contributions.append((int(pixel), int(neuron), float(values[pixel])))
    biggest = max(value for _, _, value in contributions)
    edges += [(0, src, dst, value / biggest) for src, dst, value in contributions]

    hidden = acts[0][:, None] * layers[1].weights
    biggest = float(np.abs(hidden).max())
    edges += [(1, s, d, float(hidden[s, d]) / biggest) for s, d in top_pairs(hidden, 96)]

    output = acts[1][:, None] * layers[2].weights
    biggest = float(np.abs(output).max())
    forced = [int(s) for s in np.argsort(-output[:, predicted], kind="stable")[:8]]
    chosen = [(s, predicted) for s in forced]
    chosen += [pair for pair in top_pairs(output, 64 + 8) if pair not in chosen][: 64 - len(chosen)]
    edges += [(2, s, d, float(output[s, d]) / biggest) for s, d in chosen]
    return edges


def add_glow(emit: Image.Image, spread: float = 1.0, strength: float = 1.0) -> Image.Image:
    """Bloom: emissive layer plus progressively wider blurs, added together."""
    out = emit.copy()
    for radius, gain in ((4, 0.55), (14, 0.34), (42, 0.26), (110, 0.2)):
        blurred = emit.filter(ImageFilter.GaussianBlur(radius * spread * SS))
        out = ImageChops.add(out, blurred.point(lambda v, g=gain * strength: min(255, v * g)))
    return out


def dithered(image: Image.Image) -> Image.Image:
    """Hide banding in the long dark gradients."""
    pixels = np.asarray(image, dtype=np.float32)
    noise = np.random.default_rng(7).normal(0.0, 1.1, pixels.shape[:2])[..., None]
    return Image.fromarray(np.clip(pixels + noise, 0, 255).astype(np.uint8))


def radial_background(size: tuple[int, int], center: Point, inner: Color, outer: Color, reach: float) -> Image.Image:
    w, h = size
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    distance = np.hypot(xs - center[0] * w, ys - center[1] * h) / (reach * max(w, h))
    t = np.clip(distance, 0, 1)[..., None] ** 1.3
    return Image.fromarray((np.array(inner) * (1 - t) + np.array(outer) * t).astype(np.uint8))


def diagonal_streaks(size: tuple[int, int], polygon: list[Point], bands: list[tuple[float, float]], gain: int) -> Image.Image:
    """Reflections on the pane, as an additive layer clipped to it."""
    w, h = size
    streak = Image.new("L", size, 0)
    draw = ImageDraw.Draw(streak)
    for start, width in bands:
        x0, x1 = start * w, (start + width) * w
        draw.polygon([(x0 + h * 0.45, 0), (x1 + h * 0.45, 0), (x1 - h * 0.45, h), (x0 - h * 0.45, h)], fill=gain)
    streak = streak.filter(ImageFilter.GaussianBlur(14 * SS))
    clip = Image.new("L", size, 0)
    ImageDraw.Draw(clip).polygon(polygon, fill=255)
    streak = ImageChops.multiply(streak, clip)
    return Image.merge("RGB", [streak.point(lambda v, c=c: v * c // 255) for c in (190, 225, 255)])


class Camera:
    """Pinhole camera: world units in, supersampled pixels out."""

    def __init__(self, eye: tuple[float, float, float], target: tuple[float, float, float], focal: float, center: Point):
        self.eye = np.array(eye, dtype=np.float64)
        forward = np.array(target, dtype=np.float64) - self.eye
        self.forward = forward / np.linalg.norm(forward)
        right = np.cross(self.forward, np.array([0.0, 1.0, 0.0]))
        self.right = right / np.linalg.norm(right)
        self.up = np.cross(self.right, self.forward)
        self.focal = focal
        self.center = center

    def project(self, x: float, y: float, z: float = 0.0) -> tuple[float, float, float]:
        d = np.array([x, y, z]) - self.eye
        depth = float(d @ self.forward)
        k = self.focal / depth
        return self.center[0] + float(d @ self.right) * k, self.center[1] - float(d @ self.up) * k, k


def render_thumbnail(layers: list[Layer]) -> tuple[Image.Image, int, float]:
    xs = [round(x * 65535) for x, _ in SEVEN]
    ys = [round(y * 65535) for _, y in SEVEN]
    image = preprocess(xs, ys, [len(xs)])
    assert image is not None
    acts = forward_all(layers, image)
    logits = acts[-1]
    probs = np.exp(logits - logits.max())
    probs /= probs.sum()
    predicted = int(probs.argmax())
    assert predicted == 7, f"the drawn 7 classified as {predicted}"

    size = (1920 * SS, 1080 * SS)
    W, H = size
    cam = Camera(eye=(1.7, 0.2, 21.0), target=(0.0, 0.0, 0.0), focal=1500.0 * SS, center=(1042.0 * SS, 618.0 * SS))
    back = radial_background(size, (0.62, 0.58), (20, 30, 52), (6, 8, 14), 0.72)
    emit = Image.new("RGB", size, (0, 0, 0))
    draw = ImageDraw.Draw(emit)

    half_w, half_h = 11.6, 5.45
    corners = [(-half_w, half_h), (half_w, half_h), (half_w, -half_h), (-half_w, -half_h)]
    pane = [cam.project(x, y, 0.8)[:2] for x, y in corners]
    rear = [cam.project(x, y, -1.2)[:2] for x, y in corners]

    # Floor grid running out from under the chamber.
    floor = half_h + 0.15
    for i in range(-14, 15):
        a = cam.project(i * 2.0, -floor, -14)
        b = cam.project(i * 1.0 * 2.0, -floor, 11)
        draw.line([a[:2], b[:2]], fill=(11, 32, 52), width=1 * SS)
    for j in range(13):
        z = -14 + j * j * 0.17
        a = cam.project(-40, -floor, z)
        b = cam.project(40, -floor, z)
        draw.line([a[:2], b[:2]], fill=(11, 32, 52), width=1 * SS)

    # Layer positions, as Glass lays them out: view, H1, H2, output.
    view_x, view_half = -4.95, 2.95
    view_pixel = view_half * 2 / 28
    h1_x, h2_x, out_x = 0.75, 4.55, 7.5
    h1 = [(h1_x + (c - 3.5) * 0.58, (3.5 - r) * 0.92) for r in range(8) for c in range(8)]
    h2 = [(h2_x + (c - 1.5) * 0.58, (3.5 - r) * 0.92) for r in range(8) for c in range(4)]
    out = [(out_x, (4.5 - d) * 0.92) for d in range(10)]
    positions = [h1, h2, out]

    def pixel_center(index: int) -> tuple[float, float]:
        row, col = divmod(index, 28)
        return view_x + (col + 0.5 - 14) * view_pixel, (14 - row - 0.5) * view_pixel

    # Links, faintest first so the strong ones draw on top.
    edges = select_edges(layers, image, acts, predicted)
    edges.sort(key=lambda edge: abs(edge[3]))
    for layer, src, dst, value in edges:
        a = pixel_center(src) if layer == 0 else positions[layer - 1][src]
        b = positions[layer][dst]
        strength = min(1.0, abs(value) ** 0.7)
        color = POSITIVE if value >= 0 else NEGATIVE
        pa, pb = cam.project(*a)[:2], cam.project(*b)[:2]
        draw.line([pa, pb], fill=scaled(color, 0.16 + 0.8 * strength), width=round((1 + 2.6 * strength) * SS))

    # Packets travelling along the strongest links.
    rng = np.random.default_rng(1337)
    for layer, src, dst, value in edges[-110:]:
        a = pixel_center(src) if layer == 0 else positions[layer - 1][src]
        b = positions[layer][dst]
        t = float(rng.uniform(0.2, 0.85))
        px, py, _ = cam.project(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        radius = (5.0 if value >= 0 else 3.2) * SS
        color = (215, 242, 255) if value >= 0 else (255, 190, 110)
        draw.ellipse((px - radius, py - radius, px + radius, py + radius), fill=color)

    def draw_view(target: ImageDraw.ImageDraw) -> None:
        """Exactly the model's input."""
        tl = cam.project(view_x - view_half - 0.16, view_half + 0.16)[:2]
        br = cam.project(view_x + view_half + 0.16, -view_half - 0.16)[:2]
        tr = cam.project(view_x + view_half + 0.16, view_half + 0.16)[:2]
        bl = cam.project(view_x - view_half - 0.16, -view_half - 0.16)[:2]
        target.polygon([tl, tr, br, bl], fill=(30, 40, 58))
        for index in range(784):
            row, col = divmod(index, 28)
            x0 = view_x - view_half + col * view_pixel
            y0 = view_half - row * view_pixel
            gap = view_pixel * 0.06
            quad = [
                cam.project(x0 + gap, y0 - gap)[:2],
                cam.project(x0 + view_pixel - gap, y0 - gap)[:2],
                cam.project(x0 + view_pixel - gap, y0 - view_pixel + gap)[:2],
                cam.project(x0 + gap, y0 - view_pixel + gap)[:2],
            ]
            target.polygon(quad, fill=mix(PIXEL_OFF, INK, float(image[index])))

    draw_view(draw)

    # Orbs: brightness and size follow activation.
    for layer_index, nodes in enumerate(positions[:2]):
        level = acts[layer_index] / max(1e-9, np.percentile(acts[layer_index], 97))
        for i, (x, y) in enumerate(nodes):
            amount = min(1.0, float(level[i]))
            px, py, k = cam.project(x, y)
            radius = (0.135 + 0.125 * amount) * k
            color = mix(ORB_DIM, ORB_BRIGHT, amount)
            draw.ellipse((px - radius, py - radius, px + radius, py + radius), fill=color)
            if amount > 0.5:
                core = radius * 0.5
                draw.ellipse((px - core, py - core, px + core, py + core), fill=mix(color, (255, 255, 255), 0.35))

    # Output column: the winner gets a halo. Labels and bars go on after the bloom so they stay sharp.
    for digit, (x, y) in enumerate(out):
        p = float(probs[digit])
        px, py, k = cam.project(x, y)
        win = digit == predicted
        radius = (0.36 if win else 0.2 + 0.1 * p) * k
        if win:
            halo = radius * 1.5
            draw.ellipse((px - halo, py - halo, px + halo, py + halo), outline=ORB_BRIGHT, width=round(4 * SS))
        color = mix(ORB_DIM, ORB_BRIGHT, p**0.5 * 0.55 + 0.25) if not win else (225, 247, 255)
        draw.ellipse((px - radius, py - radius, px + radius, py + radius), fill=color)
        if win:
            bar_end = cam.project(x + 3.75, y)[0]
            bar_start = cam.project(x + 1.3, y)[0]
            half = 0.2 * k
            draw.rounded_rectangle((bar_start, py - half, bar_end, py + half), half, fill=scaled(WINNER_BAR, 0.8))

    def draw_outputs(target: ImageDraw.ImageDraw) -> None:
        for digit, (x, y) in enumerate(out):
            p = float(probs[digit])
            px, py, k = cam.project(x, y)
            win = digit == predicted
            label = font((0.72 if win else 0.5) * k, "Bold")
            target.text((cam.project(x + 0.86, y)[0], py), str(digit), font=label, anchor="mm", fill=INK if win else MUTED)
            bx0 = cam.project(x + 1.3, y)[0]
            bx1 = cam.project(x + 3.75, y)[0]
            half = (0.2 if win else 0.11) * k
            target.rounded_rectangle((bx0, py - half, bx1, py + half), half, fill=BAR_BACK)
            fill_to = bx0 + max(2 * half, (bx1 - bx0) * p)
            target.rounded_rectangle((bx0, py - half, fill_to, py + half), half, fill=WINNER_BAR if win else BAR)

    # Neon trim and rear frame.
    draw.polygon(rear, outline=(24, 58, 92), width=3 * SS)
    draw.line(pane + [pane[0]], fill=(70, 180, 255), width=7 * SS, joint="curve")

    composed = ImageChops.add(back, add_glow(emit))
    crisp = ImageDraw.Draw(composed)
    draw_view(crisp)
    draw_outputs(crisp)

    # The fake-glass pane itself: a faint tint plus reflections.
    tint = Image.new("L", size, 0)
    ImageDraw.Draw(tint).polygon(pane, fill=16)
    composed = Image.composite(Image.new("RGB", size, (150, 200, 255)), composed, tint)
    composed = ImageChops.add(
        composed, diagonal_streaks(size, pane, [(0.47, 0.05), (0.535, 0.016), (0.84, 0.07)], 15)
    )

    composed = composed.convert("RGBA")
    composed = paste_tablet(composed, SEVEN)
    draw_title(composed)
    return composed.convert("RGB"), predicted, float(probs[predicted])


def paste_tablet(canvas: Image.Image, stroke: list[Point]) -> Image.Image:
    """The Pad, in the foreground on the left, with the drawing that started all this."""
    pad = 450 * SS  # tablet body
    margin = 40 * SS
    layer = Image.new("RGBA", (pad + 2 * margin, round(pad * 1.17) + 2 * margin), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    body = (margin, margin, margin + pad, layer.height - margin)
    draw.rounded_rectangle(body, 34 * SS, fill=(*TABLET, 255), outline=(*TABLET_STROKE, 255), width=4 * SS)
    inset = 24 * SS
    screen = (margin + inset, margin + inset, margin + pad - inset, margin + pad - inset)
    draw.rounded_rectangle(screen, 18 * SS, fill=(*SURFACE, 255), outline=(90, 170, 255, 255), width=3 * SS)

    # Faint button row along the lower edge, like the real Pad.
    button_top = screen[3] + 18 * SS
    button_h = layer.height - margin - button_top - 18 * SS
    usable = screen[2] - screen[0]
    for i, color in enumerate(((38, 46, 66), (38, 46, 66), (40, 110, 200))):
        x0 = screen[0] + i * (usable + 14 * SS) / 3
        x1 = x0 + (usable - 28 * SS) / 3
        draw.rounded_rectangle((x0, button_top, x1, button_top + button_h), 10 * SS, fill=(*color, 255))

    # Ink, with its own glow.
    ink = Image.new("L", layer.size, 0)
    ink_draw = ImageDraw.Draw(ink)
    sw, sh = screen[2] - screen[0], screen[3] - screen[1]
    path = [(screen[0] + x * sw, screen[1] + y * sh) for x, y in stroke]
    width = round(26 * SS)
    ink_draw.line(path, fill=255, width=width, joint="curve")
    for x, y in (path[0], path[-1]):
        ink_draw.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=255)
    glow = ink.filter(ImageFilter.GaussianBlur(12 * SS)).point(lambda v: min(255, int(v * 0.8)))
    layer.paste(Image.new("RGBA", layer.size, (70, 180, 255, 255)), (0, 0), glow)
    layer.paste(Image.new("RGBA", layer.size, (*INK, 255)), (0, 0), ink)

    layer = layer.rotate(5.0, resample=Image.Resampling.BICUBIC, expand=True)

    # Drop shadow so it sits in front of the Glass.
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    x, y = 6 * SS, 448 * SS
    alpha = layer.getchannel("A").point(lambda v: v * 0.75)
    shadow.paste((0, 0, 0, 255), (x + 14 * SS, y + 22 * SS), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(26 * SS))
    out = Image.alpha_composite(canvas, shadow)
    out.alpha_composite(layer, (max(x, 0), y))
    return out


def draw_title(canvas: Image.Image) -> None:
    title_font = font(124 * SS)
    x, y = 52 * SS, 22 * SS
    glow = Image.new("RGB", canvas.size, (0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    first = "NEURAL "
    glow_draw.text((x, y), first, font=title_font, fill=(255, 255, 255))
    second_x = x + glow_draw.textlength(first, font=title_font)
    glow_draw.text((second_x, y), "GLASS", font=title_font, fill=POSITIVE)
    halo = glow.filter(ImageFilter.GaussianBlur(20 * SS)).point(lambda v: v // 2)
    rgb = ImageChops.add(canvas.convert("RGB"), halo)
    canvas.paste(rgb)
    draw = ImageDraw.Draw(canvas)
    draw.text((x, y), first, font=title_font, fill=(*INK, 255))
    draw.text((second_x, y), "GLASS", font=title_font, fill=(*ORB_BRIGHT, 255))


def render_logo() -> Image.Image:
    """A 7 drawn as a neural path: orbs joined by beams, behind a glass pane. Full-bleed; Roblox rounds it."""
    side = 1024 * SS
    size = (side, side)
    back = radial_background(size, (0.5, 0.45), (20, 34, 62), (6, 8, 15), 0.78)
    emit = Image.new("RGB", size, (0, 0, 0))
    draw = ImageDraw.Draw(emit)

    def at(x: float, y: float) -> Point:
        return x * side, y * side

    spine = [at(0.27, 0.285), at(0.73, 0.285), at(0.585, 0.53), at(0.44, 0.765)]

    # Faint incoming layer, fanning into the spine, so it reads as a network and not just a numeral.
    feeders = [at(0.145, y) for y in (0.42, 0.53, 0.64, 0.75)]
    fans = [(0, 0), (0, 2), (1, 0), (1, 2), (2, 2), (2, 3), (3, 2), (3, 3)]
    for f, s in fans:
        draw.line([feeders[f], spine[s]], fill=(46, 122, 184), width=7 * SS)
    outs = [at(0.855, y) for y in (0.46, 0.58, 0.70, 0.82)]
    for o, s in [(0, 1), (0, 2), (1, 2), (1, 3), (2, 2), (2, 3), (3, 3)]:
        draw.line([outs[o], spine[s]], fill=(46, 122, 184), width=7 * SS)
    draw.line([outs[2], spine[1]], fill=NEGATIVE, width=10 * SS)

    for point in feeders + outs:
        r = 0.028 * side
        draw.ellipse((point[0] - r, point[1] - r, point[0] + r, point[1] + r), fill=(70, 150, 225))

    # The numeral: thick beams with white-hot cores.
    draw.line(spine, fill=POSITIVE, width=round(0.082 * side), joint="curve")
    draw.line(spine, fill=(220, 243, 255), width=round(0.04 * side), joint="curve")
    for i, point in enumerate(spine):
        r = 0.074 * side
        draw.ellipse((point[0] - r, point[1] - r, point[0] + r, point[1] + r), fill=POSITIVE)
        c = r * 0.6
        draw.ellipse((point[0] - c, point[1] - c, point[0] + c, point[1] + c), fill=(244, 252, 255))

    # Pane trim.
    inset = 0.055 * side
    draw.rounded_rectangle((inset, inset, side - inset, side - inset), 0.13 * side, outline=POSITIVE, width=round(0.013 * side))

    composed = ImageChops.add(back, add_glow(emit, 1.3, 0.8))
    pane = [(inset, inset), (side - inset, inset), (side - inset, side - inset), (inset, side - inset)]
    composed = ImageChops.add(composed, diagonal_streaks(size, pane, [(0.60, 0.11), (0.74, 0.03)], 26))
    return composed


def save(image: Image.Image, name: str, size: tuple[int, int]) -> None:
    out = dithered(image.resize(size, Image.Resampling.LANCZOS))
    out.save(OUT_DIR / name)
    print(f"{name}: {size[0]}x{size[1]}")


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    layers = load_layers()
    thumbnail, digit, probability = render_thumbnail(layers)
    print(f"model {model_version(layers)}: drawn 7 -> {digit} at {probability:.1%}")
    save(thumbnail, "thumbnail.png", (1920, 1080))
    save(render_logo(), "logo.png", (512, 512))


if __name__ == "__main__":
    main()
