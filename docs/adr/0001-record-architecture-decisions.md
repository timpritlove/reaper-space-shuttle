# ADR-0001: Record architecture decisions

- Status: accepted
- Date: 2026-10-01

## Context

The project starts as a feasibility study and may become a published REAPER extension. Many decisions rest on facts
measured at the hardware or inside REAPER (partly inherited from stagehand, Spacer and the Show Notes extension).
Those facts and the reasons behind the decisions must survive across sessions and people.

## Decision

Architecture decisions are recorded as ADRs in `docs/adr/`, numbered, in English, using `template.md`. The index is
`docs/adr/README.md`.

## Consequences

- Every new decision about architecture, device access, REAPER integration, build or distribution gets an ADR in the
  same commit as the code.
- Measurements that are not decisions go to `docs/` (findings, spikes) and are linked from the ADRs.

## Rules

- Take the next free number from the index and add the ADR to the index.
- A change that breaks the `Rules` of an ADR needs a superseding ADR; the old one becomes
  `superseded by ADR-NNNN` and is not rewritten.
- Keep "Enforced and verified by" honest: built but not tried in REAPER or at the device is an open check.

## Enforced and verified by

- Review; the index in `docs/adr/README.md`.
