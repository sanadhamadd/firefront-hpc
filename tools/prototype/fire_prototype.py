"""Small NumPy version of the fire spread rules.

This is only used to check the rules look sensible before we write the C
version. It is slow on purpose (plain array operations) and uses numpy's own
random generator, so its output will not match the C code cell for cell.

State of a cell:
    0        unburnt
    1..B     burning, the number is how many steps it has been alight
    255      burnt out
"""
import argparse

import numpy as np

BURNT = 255

# the eight neighbours as (row offset, column offset)
NEIGHBOURS = [(dr, dc) for dr in (-1, 0, 1) for dc in (-1, 0, 1) if (dr, dc) != (0, 0)]


def smooth_noise(n, m, width, rng):
    """Random field blurred with an FFT gaussian, scaled to 0..1."""
    raw = rng.standard_normal((n, m))
    ky = np.fft.fftfreq(n)[:, None]
    kx = np.fft.fftfreq(m)[None, :]
    blur = np.exp(-(kx ** 2 + ky ** 2) * (2 * np.pi * width) ** 2 / 2)
    field = np.real(np.fft.ifft2(np.fft.fft2(raw) * blur))
    field -= field.min()
    return field / field.max()


def make_landscape(n, m, seed, river=True):
    """Returns (fuel, elevation). Fuel is 0..1, elevation in metres."""
    rng = np.random.default_rng(seed)
    fuel = 0.35 + 0.65 * smooth_noise(n, m, 6, rng)
    elevation = 120.0 * smooth_noise(n, m, 12, rng)
    if river:
        col = int(m * 0.63)
        fuel[:, col:col + 3] = 0.0
    return fuel, elevation


def padded_shift(a, dr, dc, fill):
    """Value of the neighbour at (r+dr, c+dc) for every cell (r, c)."""
    n, m = a.shape
    p = np.pad(a, 1, mode="constant", constant_values=fill)
    return p[1 + dr:1 + dr + n, 1 + dc:1 + dc + m]


def ignition_probability(burning, fuel, elevation, cell_size, wind_speed,
                         wind_dir_deg, humidity, p0, slope_coeff, wind_coeff):
    """Chance that each cell catches fire this step, from all burning neighbours."""
    wx = np.cos(np.radians(wind_dir_deg))   # wind blows towards (east, north)
    wy = np.sin(np.radians(wind_dir_deg))
    keep = np.ones(fuel.shape)              # chance of NOT igniting
    for dr, dc in NEIGHBOURS:
        dist = np.hypot(dr, dc)
        # fire moves from the neighbour to this cell: west if the neighbour is
        # to the east, north if the neighbour is to the south
        sx, sy = -dc / dist, dr / dist
        cos_angle = sx * wx + sy * wy
        wind_factor = np.exp(wind_coeff * wind_speed * (cos_angle - 1.0))
        rise = elevation - padded_shift(elevation, dr, dc, 0.0)
        slope_factor = np.exp(slope_coeff * rise / (dist * cell_size))
        src = padded_shift(burning.astype(float), dr, dc, 0.0)
        p = p0 * fuel * wind_factor * slope_factor * (1.0 - humidity) / dist
        keep *= 1.0 - np.clip(p, 0.0, 1.0) * src
    return 1.0 - keep


def one_step(state, arrival, step, burn_steps, rng, **kw):
    burning = (state >= 1) & (state <= burn_steps)
    p = ignition_probability(burning, **kw)
    ignite = (state == 0) & (rng.random(state.shape) < p)
    new = state.copy()
    new[burning] += 1
    new[state == burn_steps] = BURNT
    new[ignite] = 1
    arrival[ignite] = step
    return new


def simulate(n=140, m=140, steps=80, seed=1, burn_steps=3, cell_size=25.0,
             wind_speed=6.0, wind_dir_deg=0.0, humidity=0.2, p0=0.6,
             slope_coeff=1.5, wind_coeff=0.25, ignite_at=None, river=True):
    """Generator: yields (step, state) starting with the initial grid."""
    fuel, elevation = make_landscape(n, m, seed, river)
    rng = np.random.default_rng(seed + 1000)
    state = np.zeros((n, m), dtype=np.uint8)
    arrival = np.full((n, m), -1, dtype=np.int32)
    r0, c0 = ignite_at if ignite_at else (n // 2, m // 6)
    state[r0:r0 + 2, c0:c0 + 2] = 1
    kw = dict(fuel=fuel, elevation=elevation, cell_size=cell_size,
              wind_speed=wind_speed, wind_dir_deg=wind_dir_deg,
              humidity=humidity, p0=p0, slope_coeff=slope_coeff,
              wind_coeff=wind_coeff)
    yield 0, state, fuel
    for step in range(1, steps + 1):
        state = one_step(state, arrival, step, burn_steps, rng, **kw)
        yield step, state, fuel


def colour_image(state, fuel):
    img = np.zeros(state.shape + (3,))
    light, dark = np.array([0.65, 0.82, 0.45]), np.array([0.17, 0.55, 0.20])
    for ch in range(3):
        img[..., ch] = light[ch] * (1 - fuel) + dark[ch] * fuel
    img[fuel == 0] = [0.25, 0.55, 0.85]
    img[(state >= 1) & (state < BURNT)] = [0.95, 0.35, 0.05]
    img[state == BURNT] = [0.17, 0.18, 0.20]
    return img


def main():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--size", type=int, default=140)
    ap.add_argument("--steps", type=int, default=80)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--wind-speed", type=float, default=6.0)
    ap.add_argument("--wind-dir", type=float, default=0.0, help="degrees, 0 = towards east")
    ap.add_argument("--humidity", type=float, default=0.2)
    ap.add_argument("--out", default="prototype_fire_front.png")
    args = ap.parse_args()

    frames = [0, args.steps // 3, 2 * args.steps // 3, args.steps]
    fig, axes = plt.subplots(1, len(frames), figsize=(10, 2.9))
    shown = {}
    for step, state, fuel in simulate(args.size, args.size, args.steps, args.seed,
                                      wind_speed=args.wind_speed,
                                      wind_dir_deg=args.wind_dir,
                                      humidity=args.humidity):
        if step in frames:
            shown[step] = colour_image(state, fuel)
    for ax, step in zip(axes, frames):
        ax.imshow(shown[step], interpolation="nearest")
        ax.set_title(f"step {step}", fontsize=9)
        ax.axis("off")
    fig.tight_layout()
    fig.savefig(args.out, dpi=200)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
