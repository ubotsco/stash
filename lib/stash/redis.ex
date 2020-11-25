defmodule Stash.Redis do
  @behaviour Stash.Stage

  @default_pool_size 5

  def child_spec(opts) do
    mod = Keyword.fetch!(opts, :mod)
    redis_url = Keyword.fetch!(opts, :redis_url)
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)

    children =
      for i <- 0..(pool_size - 1) do
        %{
          id: name(mod, i),
          start: {Redix, :start_link, [redis_url, [name: name(mod, i)]]}
        }
      end

    %{
      id: name(mod),
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one, name: name(mod)]]}
    }
  end

  def get(scope, id, opts) do
    key = key(scope, id, opts)

    case command(["GET", key], opts) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, val} -> {:ok, :erlang.binary_to_term(val, [:safe])}
      {:error, err} -> {:error, err}
    end
  end

  def put(scope, id, data, opts) do
    key = key(scope, id, opts)

    case command(["SET", key, :erlang.term_to_binary(data)], opts) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, err}
    end
  end

  def get_many(scope, ids, opts) do
    keys = Enum.map(ids, &key(scope, &1, opts))

    case command(["MGET" | keys], opts) do
      {:ok, list} ->
        Enum.map(list, fn
          nil -> {:error, :not_found}
          val -> {:ok, :erlang.binary_to_term(val, [:safe])}
        end)

      {:error, err} ->
        [{:error, err}]
    end
  end

  def put_many(scope, entries, opts) do
    args =
      entries
      |> Enum.map(fn {id, data} -> [key(scope, id, opts), :erlang.term_to_binary(data)] end)
      |> List.flatten()

    case command(["MSET" | args], opts) do
      {:ok, _} -> :ok
      {:error, err} -> {:error, err}
    end
  end

  defp key(scope, id, opts) do
    mod = Keyword.fetch!(opts, :mod)
    namespace = Keyword.get(opts, :namespace, mod)
    "#{mod.scope(scope)}:#{namespace}:#{id}"
  end

  ## Redix internals

  defp command(cmd, opts), do: Redix.command(random(opts), cmd)

  defp random(opts) do
    mod = Keyword.fetch!(opts, :mod)
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    n = rem(System.unique_integer([:positive]), pool_size)
    name(mod, n)
  end

  defp name(mod), do: :"#{mod}.#{__MODULE__}"
  defp name(mod, n), do: :"#{mod}.#{__MODULE__}.#{n}"
end
