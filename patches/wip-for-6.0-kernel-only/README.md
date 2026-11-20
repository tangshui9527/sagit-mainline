# WIP patches: authored for the 6.0.0-mi6-suspend1 kernel tree

These ath10k patches (0009-0012) were authored against the R6 author's
6.0 kernel sources. They do NOT compile against 7.2.11 (struct
ath10k_hw_params has no peer_pmf_support in 7.2).

Move them back to patches/ only when building a 6.0-based kernel.
