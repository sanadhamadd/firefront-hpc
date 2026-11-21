# E5 test runs with Open MPI's default network layer

Not part of the E5 results. These are the first E5 repetition (jobs 31997–32015) and the retries of the crashed 2-node setups (32025–32030), run before the job script switched Open MPI to `ob1` with shared memory and TCP.

- 32004, 32014, 32015, 32025, 32026, 32027: 2-node runs that crashed at start-up inside UCX (`sm BTL initialization` error, then a segmentation fault in `libucs`), before our code ran.
- 32028, 32029, 32030: the same setups with `OMPI_MCA_pml=ob1 OMPI_MCA_btl=self,vader,tcp` (log label `rep=ob1tcp`); all ran with the serial checksum.
- The other runs used the default layer and finished with the serial checksum.

Kept in a folder of their own so `tools/parse_logs.py results/raw` does not mix them into the results.
