# Stash

Multi-level caches

## Installation

```elixir
def deps do
  [
    {:stash, github: "ubotsxyz/stash"}
  ]
end
```

## Usage

```elixir
# User stash, backed by API
defmodule MyApp.UserStash do
  defmodule MyApiSource do
    use Stash.Source
    def get(_ctx, id, _opts), do: MyAPI.get(ctx, id)
  end

  use Stash,
    stages: [
      local: {Stash.ETS, []},
      shared: {Stash.Redis, [redis_url: "redis://localhost:6379"]},
      api: {MyApiSource, []}
    ]

  def scope(ctx), do: ctx.team_id
end
```

```elixir
# Session stash
defmodule MyApp.SessionStash do
  use Stash,
    stages: [
      redis: {Stash.Redis, [redis_url: "redis://localhost:6379"]}
    ]

  def scope(ctx), do: ctx.user_id
end
```

```elixir
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
