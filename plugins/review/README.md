# review

The Review tab: a game's proposals and admins' reviews (runtime/review.lua).
Main menu, Online > Review, while a world folder is open.

- **Author it / Propose**: the first time, you author the game as it is now
  (its first version). After a change (saved), Propose writes the patch from
  the accepted version, signed with your key, into `<game>.review/`.
- **Update**: takes the accepted proposal over the version you have.
- An admin (a key in runtime/admins.lua) picks a proposal, looks at what it
  changes, runs it headless, then Accepts or Rejects it with a note (signed).
  Never on a game it authors.

The console has the same: `key()`, `propose(note)`, `proposals()`,
`review(i, "accept" | "reject", note)`, `update()`.
