defmodule Stash.ETS do
  @behaviour Stash.Stage

  def start_link(sid, opts \\ []) do
    {ttl, opts} = Keyword.pop(opts, :ttl, :infinity)

    opts = [name: sid] ++ ttl_opts(ttl) ++ opts
    ConCache.start_link(opts)
  end

  def child_spec(opts) do
    {sid, opts} = Keyword.pop!(opts, :sid)
    %{id: sid, start: {__MODULE__, :start_link, [sid, opts]}}
  end

  defp ttl_opts(:infinity), do: [ttl_check_interval: false]
  defp ttl_opts(ttl), do: [global_ttl: ttl, ttl_check_interval: :timer.seconds(5)]

  def get(sid, scope, id) do
    key = Stash.key(scope, id)

    case ConCache.get(sid, key) do
      nil -> {:error, :not_found}
      data -> {:ok, data}
    end
  end

  def put(sid, scope, id, data) do
    key = Stash.key(scope, id)
    ConCache.put(sid, key, data)
  end

  def get_many(sid, scope, ids) do
    for id <- ids, do: get(sid, scope, id)
  end

  def put_many(sid, scope, entries) do
    for {id, data} <- entries do
      put(sid, scope, id, data)
    end

    :ok
  end
end
