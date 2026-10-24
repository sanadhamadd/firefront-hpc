# Working together

Short notes so we do not step on each other.

- Do not push straight to `main`. Make a branch (`omp-version`, `halo-exchange`, `cuda-port`...), push it and open a pull request. Someone else reads it before it is merged.
- Keep commits small and say what they do: "Add halo exchange for strips", not "update".
- Every parallel version has to give the same checksum as the serial one for the same seed before anyone times it.
- Do not run heavy jobs on the login node. Use `sbatch`.
- Do not commit large files (data, binaries, big logs). Results that go into the report are copied into `results/` on purpose.
- If you change a timing experiment, write down what changed (flags, modules, grid size) in the pull request.
