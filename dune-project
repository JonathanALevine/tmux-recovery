(lang dune 3.17)

(name tmux-recovery)

(generate_opam_files true)

(source
 (github JonathanALevine/tmux-recovery))

(license MIT)

(authors "Jonathan Levine")

(maintainers "Jonathan Levine")

(package
 (name tmux-recovery)
 (synopsis "Inspect, plan, and safely recover tmux workspaces")
 (description
  "A native OCaml CLI and Bonsai_term TUI for conservative tmux workspace recovery.")
 (depends
  (ocaml (>= 5.2))
  (dune (>= 3.17))
  core
  core_unix
  async
  async_unix
  bonsai
  bonsai_term
  bonsai_test
  bonsai_term_test
  sqlite3
  yojson
  ppx_jane))
