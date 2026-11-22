# Final report plan

Owner: Alicia (final editor). This file decides the open questions from 22 Nov 2026, so nobody has to wait for a meeting. If you disagree, say so in the PR; otherwise this is the plan.

## Deadlines

We use the calendar dates from the team message and ignore the weekday names (they were 2025 weekdays):

| Date | What |
|---|---|
| **7 Dec** | Code and results freeze: all PRs merged, all logs and tables in `results/` |
| **12 Dec** | All report sections and slides final in `docs/` |
| **13–14 Dec** | Alicia does the final edit and puts together the PDF |
| **15 Dec** | Submission of `Group01_Part2_Final.pdf` |

If Blackboard gives a different date, the earlier date wins.

## Decisions

1. **E8 (kernel optimisation) is on, as a second optimisation (Alicia).** E7 stays the main, required optimisation. E8 adds `--skip-tiles T` (skip tiles with no fire nearby, same checksum): locally 30–60× faster, and it moves the MPI bottleneck to load imbalance and halo exchange (proposal hypothesis 4). Results freeze applies: cluster runs before 7 Dec. In the report: a short paragraph and one figure at the end of §7, the imbalance in §6.
2. **§9 Conclusions: Alicia.**
3. **§5 Results stays Alejandro's** (Sanad's role message, 21 Nov). His draft covers E3 and E4; the other experiments come as ready-made paragraphs he puts into §5: Alicia gives E1, E2, STREAM and E6 (`docs/alicia_section5_e1_e2_e6.md`, done), Sanad gives E5 (his runs).
4. **Slide 5 = additional technology + lessons learned + EuroHPC**, as the brief asks. Rodrigo presents it: the GPU result and the technology matrix, plus lessons learned. Sanad gives him one line with the EuroHPC node-hour estimate.
5. **The PDF: Alicia** puts together `Group01_Part2_Final.pdf`: report, EuroHPC plan, repo link, tag and reproducibility information.
6. **Khadeja commits the raw E7 logs** (`results/raw/e7-e9/`, anonymised) before the freeze, so E7 can be rebuilt with `tools/analyze_e7.py`.
7. **Two-node numbers:** E5 measured 4.56 s and E3/E7 3.13 s for the same 32-rank, two-node configuration. The report compares two-node runs only within one campaign and states the difference as a limitation (§4). §6 uses the E7 blocking runs as the two-node baseline, because they were measured next to the overlap runs.
8. **E9 profiling:** the application/MPI timers are our profiling tool (the brief allows this). Khadeja tries `perf stat` once before the freeze; if it is not available, §6 says so in one sentence.
9. **Experiment numbers follow the proposal:** E8 kernel optimisation (tile skipping), E9 profiling, E10 GPU. The README is updated to match (Sanad, README fixes).
10. **Final tag:** `v1.0-final` on `main` after the freeze; the PDF cites it.

## Who writes what

| Part | Owner | Pages | Status 22 Nov |
|---|---|---|---|
| E8 code, cluster runs, paragraph for §7 | Alicia | (in §7) | code + tests + job scripts done; cluster runs to do |
| §1 Problem and motivation | Alicia | 0.5 | draft (`docs/alicia_report_sections_1_2_4.md`) |
| §2 Application architecture | Alicia | 0.75 | draft (same file) |
| §3 HPC implementation | Sanad | 0.75 | to do |
| §4 Experimental methodology | Alicia | 0.75 | draft (same file) |
| §5 Results (owner, assembles) | Alejandro | 1.5 total | E3/E4 draft (`docs/alejandro_section5_results.md`) |
| └ input: E1, E2, STREAM, E6 | Alicia | 0.5 | done (`docs/alicia_section5_e1_e2_e6.md`) |
| └ input: E5 | Sanad | 0.4 | to do |
| §6 Bottleneck analysis | Khadeja | 0.75 | draft (`docs/e7-e9-report-draft.md`) |
| §7 Optimisation | Khadeja | 0.75 | draft (same file) |
| §8 Technology exploration + matrix | Rodrigo | 0.5 | to do |
| §9 Conclusions | Alicia | 0.25 | to do (after §5–§8) |
| **Report total** | | **≈ 7** | |
| EuroHPC scale-up plan | Sanad | 1–2 | to do |
| Slide 1 problem | Alicia | | draft (`docs/alicia_slide1.md`) |
| Slide 2 HPC architecture | Sanad | | to do |
| Slide 3 scaling results | Alejandro | | draft |
| Slide 4 bottleneck + optimisation | Khadeja | | draft, update to final E7 numbers |
| Slide 5 GPU, lessons, EuroHPC | Rodrigo (+ one line from Sanad) | | to do |

Pages include figures. Aim for at most 5 figures in the report: E2 scaling, E6 size sweep, E3/E4, E5 or E7 communication, GPU.

## Rules for every section

- Numbers only from `results/tables/` (cite the file in a comment); median with min–max; say how many repetitions.
- Interpret every figure in the text: what it shows and why.
- Same terms everywhere: "rank", "thread", "physical core", "halo exchange", "speed-up against serial E1 (81.95 s)".
- Put your section in `docs/` as Markdown, open a PR, and tell Alicia.

## Final edit checklist (Alicia)

- [ ] Every number checked against its CSV
- [ ] Page count 5–7 (report) + 1–2 (EuroHPC)
- [ ] Figure numbers and captions, all referred to in the text
- [ ] Technology matrix present (§8)
- [ ] Each hypothesis from the proposal answered (supported / refuted / not tested)
- [ ] REPRODUCE.md: E7, E9 and E10 sections complete; follow section 6 once from a fresh clone
- [ ] README status list and experiment numbers match the report
- [ ] Repo link, tag `v1.0-final` and reproducibility paragraph in the PDF
