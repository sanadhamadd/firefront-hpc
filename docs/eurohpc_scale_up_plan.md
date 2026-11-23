# EuroHPC scale-up plan

Draft by Sanad, 1–2 pages for the final PDF. Every measured number comes from `results/tables/` (cited in comments); every other number is an assumption and is marked as one. The GPU part stays open until the E10 CUDA runs exist; do not fill it with estimates.

<!-- per-core throughput: results/tables/e5_summary.csv, blocks, 1 node, 32 ranks: cells_per_s 9.99e9 -> 312 MCUPS per core -->
<!-- serial: E1 median 81.95 s -> 319 MCUPS (8192^2 x 390 timed steps) -->
<!-- tile skipping: results/tables/e8_summary.csv, omp 32 threads, T = 64: 10.7x, 2.6 % of tiles computed -->
<!-- two nodes: e5_summary.csv, efficiency 0.47-0.60; E7 overlap two nodes 6-14 % faster (e7_summary.csv) -->

---

## EuroHPC scale-up plan: daily wildfire-spread ensembles for Spain

**Goal.** A fire-spread forecast is only useful if it covers the uncertainty in the weather and in where a fire starts. The goal at scale is a **daily ensemble for mainland Spain at 25 m**: about 1,000 possible ignition points under 20 weather scenarios, i.e. 20,000 simulations per day during the fire season, combined into a map of the probability that each cell burns. Our course runs used one 205 × 205 km grid and 32 cores; this plan takes the measured throughput of that code to a EuroHPC system.

**Target system.** MareNostrum 5 at BSC (Barcelona), a EuroHPC system in Spain. Its general-purpose partition has 112 cores per node (2 × 56-core Intel Xeon), and its accelerated partition has 4 NVIDIA H100 GPUs per node, which our CUDA port could use without changes. LUMI-C (AMD EPYC, 128 cores per node) is closer to our test cluster's CPUs, but LUMI's GPUs are AMD, so the CUDA version would need porting. Node sizes must be checked against the current call documentation.

**Problem size.**

| Quantity | Value | Source |
|---|---|---|
| Area | ≈ 500,000 km² (mainland Spain) | assumption |
| Cells at 25 m | 8.0 × 10⁸ (1,600 per km²) | from the area |
| Memory per simulation | ≈ 8 GB (10 bytes per cell) | from our data layout (§2) |
| Steps per simulation | 2,000 (a fire moves at most one cell per step, so up to 50 km) | assumption |
| Cell updates per simulation | 1.6 × 10¹² | cells × steps |

**Measured throughput.** On our cluster one core performs **312 million cell updates per second** in the MPI version (32 ranks, blocks, one node, efficiency 0.98), the same as the serial code (319 million). Throughput is the same for every grid size from 2048² to 16384² (E6), because the kernel is limited by computation, not memory bandwidth. So it should carry over to a larger grid. Assuming the same speed per core on MareNostrum 5 and 90 % efficiency on a full 112-core node (we measured 0.98 on 32 cores; the rest is an assumption to be checked), one node performs 3.1 × 10¹⁰ updates per second.

**How the work is laid out.** Our results decide the layout:
- **One simulation per socket, MPI ranks inside it.** 8 GB fits easily on one node, so no simulation needs to cross nodes. Inside a node MPI with blocks scaled almost ideally (efficiency 0.94–1.01 up to 32 ranks, E5).
- **The ensemble across nodes.** Simulations are independent, so many nodes run different simulations at the same time and only the final burn maps are combined. This avoids the cost we measured between nodes: efficiency fell to 0.47–0.60 on two nodes, with 43–56 % of the run in the halo exchange (E5). Overlap recovered only 6–14 % of that (E7).
- **Tile skipping on.** Most of the grid is far from the fire. Skipping those tiles made 32 OpenMP threads 10.7× faster with the same result (E8, 2.6 % of tiles computed). The gain shrinks as fires grow, so we budget without it and treat it as savings.

**Node-hour estimate.**

| | Work | Node-hours |
|---|---|---|
| One simulation | 1.6 × 10¹² updates / 3.1 × 10¹⁰ per s = 51 s | 0.014 |
| One day (20,000 simulations) | | **≈ 280** (under 3 h on 100 nodes) |
| One-month pilot (30 days) | | ≈ 8,500 |
| One fire season (120 days) | | **≈ 34,000** |
| Season with tile skipping (assume 5×, measured 10.7×) | | ≈ 7,000 |

At 10 m resolution the work grows 15.6× (6.25× more cells, 2.5× more steps) and a simulation needs about 50 GB, which still fits on one node: about 4,400 node-hours per day, so a season at 10 m would need a much larger allocation.

**Access route.**
1. **Benchmark Access** (≈ 100 node-hours): build with the system's compilers and MPI, check the serial checksum, measure the speed per core and the scaling to 112 cores, test one 8 × 10⁸-cell simulation, and run the CUDA version on one H100 node. This replaces our assumptions with measured numbers.
2. **Development or Regular Access**, depending on size: the one-month pilot (≈ 8,500 node-hours, or less with tile skipping), then a full season (≈ 34,000 node-hours without tile skipping).

**GPU option.** *(Open until E10.)* If the CUDA version beats the best 32-core CPU run on the RTX 6000 Ada of our cluster, the accelerated partition is the better target: one H100 node would run four simulations at once. The estimate in GPU-node-hours is added once `results/tables/e10_summary.csv` has CUDA rows.

**Risks.**
- **Speed per core on another CPU** is assumed, not measured. Benchmark Access measures it first.
- **Load imbalance with tile skipping:** with MPI the ranks that hold the fire do all the work (imbalance up to 3.2, E8). One simulation per socket with OpenMP tiles, which are handed out dynamically, avoids most of it.
- **Real data:** our landscape is synthetic. Real fuel maps and terrain (e.g. Copernicus land cover, IGN elevation) have to be prepared and split, and the model has to be calibrated against past fires before its maps mean anything.
- **Output:** storing every simulation (0.8 GB of states each) would cost more than computing it, so each node adds its results into one burn-probability map. We did not measure output cost.

**One line for slide 5:** A daily Spain-wide ensemble at 25 m (20,000 simulations) needs about 280 node-hours on MareNostrum 5, about 34,000 node-hours for a 120-day fire season, roughly 5× less with tile skipping.
