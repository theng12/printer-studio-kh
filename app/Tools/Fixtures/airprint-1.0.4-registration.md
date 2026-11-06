# AirPrint registration fixture provenance

The registration layout comes from `9d263a1`, the released 1.0.4 bridge. The TSC and Xprinter queue identifiers, descriptions and host name come from the owner's 2026-11-06 iMac report. Each `.txt` fixture is the exact argument vector, one argument per line, expected at `dns-sd -R`.

The legacy instance suffix, service/subtype, domain, port, TXT keys/order, queue-based note, PDL and URF marker are restored. Later UUID and psbridge additions are absent.

One capability correction is deliberately retained: `lpoptions -p <queue> -l` selects the target before listing options, and capability values are parsed separately from UI labels. Therefore both label queues correctly use Color=F and Duplex=F even when the Mac's default Brother queue offers duplex. This is the documented difference from 1.0.4's option-query bug; these fixtures do not claim to reproduce that bug.

The adversarial DNS-SD mock offers matching local Printer Sharing records without a URF TXT field. The old native-record classification can suppress them. The restored bridge must register both label queues and the Brother regardless. This is an offline regression scenario, not proof that native-record skipping caused the owner's specific failure.

An actual iPhone visibility check is still required.
