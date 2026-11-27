# Help wanted

Ethan Protocol is open to contributions. Below is the hardening work that would make it stronger, roughly in order of impact. Pick anything, comment on (or open) an issue so others know you are on it, and see [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

Found a vulnerability instead? Please report it privately, see [SECURITY.md](SECURITY.md).


### Independent smart contract audit

**High impact.** Ethan holds a live USDC treasury on Base. Independent review of `Router`, `ProposalRegistry` and `Constitution` is the most valuable contribution there is.

### Static analysis in CI

**Medium.** Add Slither (pinned by commit) to CI and triage its findings, documenting any accepted ones.

### More invariants

**Medium.** Extend `test/Invariant.t.sol`: total assets never decrease except through an executed, timelocked proposal, and so on.
