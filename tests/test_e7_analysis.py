"""Local regression checks for the E7 parser, using synthetic records only."""

from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from analyze_e7 import REFERENCE, read_pairs, summarize, write_csv


def fixture(rep=1, baseline=6, overlap=4):
    common = (f"RESULT variant=mpi nx=8192 ny=8192 steps=400 seed=42 ignitions=16 "
              f"checksum={REFERENCE} humidity=0.2 commit=abc compiler=gcc nodes=2 "
              "ranks=8 threads=1 places=cores decomp=blocks px=4 py=2")
    return "\n".join((
        f"PAIR rep={rep} profile=none commit=abc binary_sha=fixture transport=fixture allocation=A,B",
        f"VERIFIED checksum={REFERENCE}",
        f"{common} overlap=0 t_total={baseline} t_halo=2 t_compute=3 t_reduce=0 imbalance=1.25",
        f"{common} overlap=1 t_total={overlap} t_halo=1 t_compute=3 t_reduce=0 imbalance=1.10"
        " t_post=0.25 t_wait=0.75 t_interior=2 t_boundary=1",
        "PAIR COMPLETE",
    ))


class E7AnalysisTest(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)

    def log(self, name, content):
        path = self.directory / f"e7_overlap_{name}.out"
        path.write_text(content, encoding="utf-8")
        return path

    def test_pair_statistics_and_csv(self):
        paths = [self.log(101, fixture()), self.log(102, fixture(2, 9, 6))]
        pairs = list(read_pairs(paths))
        summary, = summarize(pairs)
        self.assertEqual(summary["pairs"], 2)
        self.assertEqual(summary["blocking_median"], 7.5)
        self.assertEqual(summary["overlap_median"], 5)
        self.assertEqual(summary["blocking_min"], 6)
        self.assertEqual(summary["overlap_max"], 6)
        self.assertEqual(summary["optimization_speedup"], 1.5)
        self.assertAlmostEqual(summary["improvement_pct"], 100 / 3)
        csv_path = self.directory / "e7_runs.csv"
        write_csv(csv_path, [row for pair in pairs for row in pair])
        self.assertIn("t_wait", csv_path.read_text(encoding="utf-8").splitlines()[0])

    def test_incomplete_and_profiled_jobs_are_excluded(self):
        incomplete = self.log(101, fixture().replace("PAIR COMPLETE", ""))
        profiled = self.log(102, fixture().replace("profile=none", "profile=perf"))
        self.assertEqual(list(read_pairs([incomplete, profiled])), [])

    def test_missing_verification_mixed_builds_and_duplicate_reps_are_rejected(self):
        missing = self.log(101, fixture().replace("VERIFIED", "FAILED"))
        with self.assertRaisesRegex(ValueError, "missing untimed verification"):
            list(read_pairs([missing]))
        first = self.log(102, fixture())
        mixed = self.log(103, fixture(2).replace("binary_sha=fixture", "binary_sha=other"))
        with self.assertRaisesRegex(ValueError, "Mixed builds"):
            list(summarize(read_pairs([first, mixed])))
        duplicate = self.log(104, fixture())
        with self.assertRaisesRegex(ValueError, "Duplicate repetition"):
            list(summarize(read_pairs([first, duplicate])))

    def test_inconsistent_phase_times_are_rejected(self):
        path = self.log(101, fixture().replace("t_wait=0.75", "t_wait=0.25"))
        with self.assertRaisesRegex(ValueError, "inconsistent t_halo"):
            list(read_pairs([path]))


if __name__ == "__main__":
    unittest.main()
