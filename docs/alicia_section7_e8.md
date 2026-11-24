# Report draft: second optimisation (E8), for the end of §7

Draft by Alicia, to add after Khadeja's E7 part of §7 (`docs/e7-e9-report-draft.md`). Target ≈ 0.4 page with one figure. All numbers from `results/tables/e8_summary.csv` (cluster jobs 35403–35428, commit `76221f5`, median of 3, every run gave the reference checksum). The last paragraph is input for Khadeja's §6.

---

**Second optimisation: skipping tiles without fire (E8).** E7 attacked communication. The E2 and E6 results point at a different target: the cell update is limited by computation, yet in our runs almost all cells are unburnt with no burning neighbour, and the update only copies their state. `--skip-tiles T` cuts each rank's block into T × T tiles and skips every tile that has no burning cell in it or on its one-cell rim. Such cells cannot change and draw no random number, so the result stays bit for bit the same (checksum `0xb8683c550fa95bd6` in all 63 runs). Each before/after pair ran in the same Slurm job or allocation.

The gain is large: the serial run drops from 86.85 s to 1.45 s (**60×**), 32 OpenMP threads from 2.36 s to 0.22 s (10.7×, T = 64), and the fastest configuration, 32 MPI ranks on one node, needs **0.147 s**, 590 times less than the serial run without skipping. The tile size matters: with T = 8 only 0.3 % of the tile updates are computed, but bookkeeping for a million tiles makes the run slightly slower than no skipping at all; T = 64 is best (2.6 % computed); with T = 128, too many quiet cells are computed again (6.7 %).

*Place Figure here:* `results/figures/e8_before_after.png`. **Caption.** Time without (blue) and with tile skipping (T = 32) for the 8192² problem, median of 3 with min–max; numbers are the speed-ups. Log scale.

**The bottleneck moves.** Once the work is gone, the program no longer scales. With skipping, OpenMP gains only 5× from 1 to 8 threads (1.42 → 0.28 s) and nothing beyond (0.32 s at 16, 0.28 s at 32 threads): about 0.7 ms per step remain, and fixed costs per step (starting the parallel loop, checking every tile, the serial end-of-step bookkeeping) are a large part of it; we did not time them separately. With MPI the speed-up falls as ranks are added (26× at 8, 20× at 16, 16× at 32 ranks, 5× on two nodes), because the fire burns in a few places: the compute imbalance rises from 1.05–1.09 to 1.8, 2.5 and 3.2, and ranks without fire wait in the halo exchange, which grows from 7–21 % to 79–96 % of the run. This confirms hypothesis 4 of the proposal. The next step would be to balance the burning tiles over the ranks, e.g. fewer ranks with more threads each, because the OpenMP tile loop already hands out tiles dynamically.

*Optional second figure (or move to §6):* `results/figures/e8_mpi_balance.png`. **Caption.** MPI ranks without and with tile skipping: (a) compute imbalance (slowest / average rank), (b) share of the run spent in the halo exchange, which includes waiting for slower neighbours.

---

**For Khadeja (§6):** E8 shows a second bottleneck after the work per cell is removed: load imbalance. With skipping, `imbalance` reaches 3.2 at 32 ranks and the halo time (mostly waiting for the ranks that hold the fire) is 88 % of the run on one node and 96 % on two. Without skipping both stay low (imbalance ≤ 1.09, halo 7–21 %). Numbers in `results/tables/e8_summary.csv`, figure `results/figures/e8_mpi_balance.png`.

**For §4 (limitations):** the E8 serial/OpenMP jobs got cores 0–31 (four whole chiplets) on a quiet node, and their 32-thread run without skipping took 2.36 s, against 3.24 s in E2 (cores 14–45, other jobs on the node). Results are therefore compared only within one campaign.
