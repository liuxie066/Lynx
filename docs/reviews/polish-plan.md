# Native interface polish

Base: c83a59894bdd83398ac54e87a979677ef91c3022. User authorized autonomous improvement, isolated worktree, commit and PR; no merge or release.

## Goal and scope

Keep the approved four pages, market switch, two strategy cards and existing finance rules. Deliver a coherent native hierarchy, accessible controls, useful empty/loading states and bounded large-table layout. No new runtime dependencies or services. Completion requires passing tests, native build, review of the final diff and a verified PR. Native screen inspection is attempted only through the host computer tool; unavailable screen access is reported rather than bypassed.

## Evidence and plan check

OptionsCard currently evaluates/formats rows twice, searches all stock results for every representative and sets table height to every expanded row. A large option chain therefore expands the whole page rather than retaining a bounded native table viewport. Styles duplicate 18/20/22/24/26-point spacing and native focus/labels are missing on some controls. Empty results always suggest refreshing even after a complete scan.

1. Reuse native controls and the existing ice-blue palette; centralize card/header/empty-state presentation, normalize typography, numeric alignment, footer separators and accessibility. Keep main content order.
2. Build table presentation once per body with an indexed stock lookup; cap native table height, preserve all candidates and trailing disclosure. Correct empty-state messaging and add direct configuration navigation.
3. Avoid reading agent installation files on every SwiftUI body evaluation; inspect on page appearance, app activation and after explicit install actions. Do not introduce background processes or caches for finance calculations.
4. Test presentation order, expanded hierarchy, missing data and a large result fixture; run existing full tests and Xcode build. Inspect actual UI if unlocked, then review and deliver.

Plan check: scoped presentation changes, no new public API/persistence/financial semantics. No separate architecture review required. Synchronous persistence is retained to preserve existing write receipts; redesigning it is not justified by measured evidence in this iteration.

Residual scope: OS notification delivery/login startup, external Agent discovery and HK live-market acceptance remain assigned to the existing DEVELOPMENT manual checklist. This work does not claim to complete those external checks.
