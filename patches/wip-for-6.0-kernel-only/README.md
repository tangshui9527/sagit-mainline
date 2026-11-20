# WIP patches: NOT compatible with the 7.2.11 CI build

0001 (dts remoteproc enable) and 0002 (rmtfs oem partitions) were authored
against a different dts state. Applied to the 7.2.11 CI build they corrupt
the DTB and the kernel hangs at early boot (all M2 dark boots traced here).

0009-0012 (ath10k) are authored for the 6.0 kernel tree (peer_pmf_support
does not exist in 7.2 ath10k).

0003 is a JSON mapping (not applied by the CI).
