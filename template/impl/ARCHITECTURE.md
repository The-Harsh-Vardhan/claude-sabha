# Architecture

Owner: the architect role. Updated when a design changes, in the same change as the decision (DECISIONS.md). Keep each
section short; link to code instead of copying it.

## Purpose

One paragraph: what this system is for and who uses it. State the problem, not the features.

## Context and boundaries

What is inside this project, what is outside, and which external systems it talks to. One line per neighbour: what
crosses the boundary and in which direction.

## Diagram

One ASCII diagram of the main parts and how data moves. Update it when a box is added or removed; a stale diagram is
worse than none.

## Components

One line each: name, path, one responsibility. If a component has two responsibilities, say so; it is a candidate to
split.

## Data and state

Where data lives, who writes it, who reads it, and what is the source of truth. Name every store and its lifetime.

## Key flows

The two or three flows that matter most, as numbered steps. Include the failure path of each, not only the happy one.

## Contracts

Interfaces other code or other repositories depend on (APIs, schemas, file formats). Say who owns each and what breaks
when it changes.

## Constraints

Hard limits the design must respect: performance, cost, security, compatibility. Each with the reason, so it can be
revisited when the reason goes away.

## Open questions

Things not decided yet, each with the decision number in DECISIONS.md that will settle it.
