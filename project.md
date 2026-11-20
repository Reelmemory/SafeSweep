# SafeSweep

**Keeperless Emergency Fund Evacuation using Reactive Contracts**

> When something looks wrong, funds move themselves. No bot. No keeper. No one needs to be online.

## One-Line Pitch

A Reactive-powered protection layer that watches for high-signal compromise events and autonomously sweeps remaining funds to a pre-approved safe wallet — across chains if needed.

## The Problem

Most users only discover a wallet compromise after funds are already gone. Existing solutions require:

- The user to be online and notice in time
- A running bot or keeper
- Manual multi-sig coordination
- Or a simple time-lock that still leaves a window

By the time a human reacts, it’s usually too late.

## What Reactive Makes Possible

Reactive Contracts can **watch an event on any supported chain and autonomously fire a real transaction elsewhere** with no keeper and no one online.

SafeSweep uses exactly this:

1. A suspicious or panic event occurs on the origin chain
2. The Reactive Contract evaluates the condition
3. It fires a callback that sweeps funds to a pre-approved destination (same chain or different chain)

This is the loop Reactive judges look for: **origin event → Reactive logic → destination callback**, proven with real transaction hashes.

## How It Works

### Protected Wallet / Vault
- User deposits funds into a simple vault contract (or protects an existing wallet via approvals + monitored events).
- Destination address is set with a safety delay (time-lock or guardian co-approval) so a compromised key cannot instantly change where funds go.

### Triggers (high-signal only)
- Large or unexpected outgoing transfer
- Interaction with a known malicious contract
- Explicit panic signal from a guardian / hardware wallet / secondary key
- Optional: missed heartbeat (no “I’m alive” transaction within N days)

### Reactive Reaction
- Reactive Contract is subscribed to the relevant events.
- On trigger it checks conditions and immediately calls the destination contract to sweep remaining balances (and optionally revoke approvals).

### Result
- Funds arrive in the pre-approved safe wallet.
- Clear on-chain events explain *why* the sweep happened.
- Original wallet is drained or locked.

## Why This Is a Strong Contender

| Criteria Reactive rewards | How SafeSweep delivers |
|---------------------------|------------------------|
| Real reactive loop with tx hashes | Origin event + Reactive tx + destination callback, all shown |
| Reactive does real work | The decision and execution happen inside the Reactive Contract |
| Solves a real pain | Funds lost while the owner is offline or asleep |
| Would be worse without Reactive | Requires a always-on bot or human reaction otherwise |
| Showable in ~30 seconds | Trigger → sweep → funds arrived |
| Craft | Small, readable contracts + clear docs + working demo |

It stays sharp instead of becoming a generic payments or treasury app.

## Minimal Demo Flow (30–60 seconds)

1. Show protected vault with funds
2. Emit a panic event or simulate a suspicious large transfer
3. Show the Reactive transaction fire
4. Show destination wallet receive the funds
5. Show the explanation event on-chain

That’s the entire loop judges need to see.

## Tech Scope (Hackathon-sized)

- Origin / Vault contract (simple deposit + trigger events)
- Reactive Contract (subscription + condition check + callback)
- Destination / Safe Wallet contract (receive + optional lock)
- Deployed on supported testnets (Lasna + one or two origin/destination chains)
- Public repo with deploy scripts and clear README
- Short demo video + transaction hashes of the full loop

## Extra Tight Tips

- **Lead with the reactive loop**, not the product story. The first 30 seconds of the demo and the first paragraph of the README should show event → Reactive → callback.
- **One primary trigger** is enough. Adding too many conditions makes the demo slower and the code messier.
- **Destination address must be hard to change** (time-lock or guardian). This is the difference between a useful tool and an obvious attack vector.
- **Provide the three transaction hashes** (origin, Reactive, destination) in the submission. This is what separates projects that actually ran from projects that only described the idea.
- **Keep the contracts small**. Judges prefer a clean, working reactive loop over a large unfinished system.
- **Fit the “Set It and Forget It” track**. The pitch is: “I can leave this running and trust it will act if something goes wrong.”
- **Do not overbuild yield, tuition, or complex DeFi**. Those can be future extensions. The core must stay the autonomous sweep.

## Possible Future Extensions (not needed for submission)

- Multi-chain coordinated sweep
- Optional yield while protected
- Integration with specific lending protocols
- Guardian network / social recovery signals

## Submission Checklist

- [ ] Public repo with Reactive + destination contracts
- [ ] Deployed addresses
- [ ] Transaction hashes showing the full loop
- [ ] Demo video under 3 minutes
- [ ] Clear README explaining the problem Reactive solves
- [ ] Track selected: Set It and Forget It

---

**SafeSweep** — Funds that move themselves when it matters.
