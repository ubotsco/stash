# Stash

Multi-level caches

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `stash` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:stash, "~> 0.1.0"}
  ]
end
```

## Usage

```ex
# User stash, backed by API
defmodule MyApp.UserStash do
  defmodule Source do
    use Stash.Source
    def get(_ctx, id, _opts), do: MyAPI.get(ctx, id)
  end

  use Stash,
    stages: [
      Stash.ETS,
      {Stash.Redis, [redis_url: "redis://localhost:6379"]},
      Source
    ]

  def scope(ctx), do: ctx.team_id
end
```

```ex
# Session stash
defmodule MyApp.SessionStash do
  use Stash,
    stages: [
      {Stash.Redis, [redis_url: "redis://localhost:6379"]}
    ]

  def scope(ctx), do: ctx.user_id
end
```

```ex
# Start both in you application
defmodule MyApp do
  use Application

  def start(_type, _args) do
    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  def children do
    [
      MyApp.UserStash,
      MyApp.SessionStash
    ]
  end
end
```
