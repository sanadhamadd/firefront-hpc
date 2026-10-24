# data

Small inputs only. Nothing large goes into git.

- Synthetic landscapes are built by the program from a size and a seed, so no input file is needed for the scaling experiments.
- Real terrain (optional): elevation from the IGN MDT or Copernicus GLO-30, land cover from Copernicus CORINE. `tools/make_landscape.py` will download or read these and write a flat binary into `data/real/`, which is ignored by git. Instructions will be added when the script exists.
