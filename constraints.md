# Personal constraints example — ~/.gatespec/constraints.md
#
# Standing user-level constraints, loaded by gatespec.specify / gatespec.plan
# alongside the project constitution (project constitution wins on conflict).
# gatespec.plan offers a one-time merge of this file into the project
# constitution so upstream phases (tasks/implement) also obey it.

## Engineering principles

1. **No over-design for unreachable error paths.** Error cases that are
   theoretically near-impossible and whose trigger would itself indicate a
   design error are acceptable as-is — do not build complex fallback
   mechanisms for them.

2. **Tests must not pollute production APIs.** Tests may drive improvements
   to module boundaries, dependency graphs, and observability — but do NOT
   add production APIs, states, branches, or behaviors that have no real
   business use just for testing. Test control needs should be met through
   existing public contracts, dependency injection, or test-side doubles.

## C++ coding standards

3. **One class per file pair.** Every class gets its own `.h` and `.cpp`;
   never host multiple class implementations in one source file.

4. **Google C++ Style.** Follow the Google C++ Style Guide.

## Design detailing expectations (extends the gatespec six dimensions)

Designs should spell out: thread model, memory/object lifetimes, key module
classes, key APIs and their interactions, external interface behavior, and
setup/runtime/teardown phase interactions.
