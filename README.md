# Raft1

To change parameters, just change the config in DAC.ex.
To change the number of clients and/or servers, update Makefile.
To change server sleep time, update leader.ex, candidate.ex and follower.ex

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `raft1` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:raft1, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/raft1](https://hexdocs.pm/raft1).

