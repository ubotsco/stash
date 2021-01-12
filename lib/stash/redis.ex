defmodule Stash.Redis do
  defmodule Expirer do
    use GenServer

    def start_link(sid, ttl), do: GenServer.start_link(__MODULE__, {sid, ttl}, name: name(sid))

    def expire(sid, key), do: GenServer.cast(name(sid), {:expire, key})

    def init({sid, ttl}) do
      {:ok, %{sid: sid, ttl: ttl}}
    end

    def handle_cast({:expire, key}, %{sid: sid, ttl: ttl} = state) do
      do_expire(sid, key, ttl)
      {:noreply, state}
    end

    defp do_expire(sid, keys, ttl) when is_list(keys) do
      for key <- keys, do: do_expire(sid, key, ttl)
    end

    defp do_expire(sid, key, ttl) do
      Stash.Redis.command(sid, ["EXPIRE", key, ttl])
    end

    def name(sid), do: :"#{sid}.Expirer"
  end

  defmodule Leader do
    use GenServer

    def start_link(sid, size), do: GenServer.start_link(__MODULE__, {sid, size}, name: name(sid))

    def command(sid, cmd) do
      size = GenServer.call(name(sid), :size)
      n = rem(System.unique_integer([:positive]), size)
      Redix.command(name(sid, n), cmd)
    end

    def init({sid, size}) do
      {:ok, %{sid: sid, size: size}}
    end

    def handle_call(:size, _from, %{size: size} = state) do
      {:reply, size, state}
    end

    def name(sid), do: :"#{sid}.Leader"
    def name(sid, n), do: :"#{sid}.Conn.#{n}"
  end

  @behaviour Stash.Stage

  alias Stash.Redis.Expirer

  def start_link(sid, opts) do
    {ttl, opts} = Keyword.pop(opts, :ttl, :infinity)
    {size, opts} = Keyword.pop(opts, :pool_size, 5)
    {redis_url, opts} = Keyword.pop!(opts, :redis_url)

    workers =
      for i <- 0..(size - 1) do
        redis_opts = Keyword.put_new(opts, :name, Leader.name(sid, i))

        %{
          id: Leader.name(sid, i),
          start: {Redix, :start_link, [redis_url, redis_opts]}
        }
      end

    leader = %{
      id: Leader.name(sid),
      start: {Leader, :start_link, [sid, size]}
    }

    expirer = %{
      id: Expirer.name(sid),
      start: {Expirer, :start_link, [sid, ttl]}
    }

    children = [leader, expirer | workers]
    Supervisor.start_link(children, strategy: :one_for_one, name: sid)
  end

  def child_spec(opts) do
    {sid, opts} = Keyword.pop!(opts, :sid)

    %{
      id: sid,
      type: :supervisor,
      start: {__MODULE__, :start_link, [sid, opts]}
    }
  end

  def get(sid, scope, id) do
    key = key(sid, scope, id)

    case command(sid, ["GET", key]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, val} -> {:ok, :erlang.binary_to_term(val, [:safe])}
      {:error, err} -> {:error, err}
    end
  end

  def put(sid, scope, id, data) do
    key = key(sid, scope, id)

    case command(sid, ["SET", key, :erlang.term_to_binary(data)]) do
      {:ok, _} ->
        Expirer.expire(sid, key)
        :ok

      {:error, err} ->
        {:error, err}
    end
  end

  def get_many(_sid, _scope, []), do: []

  def get_many(sid, scope, ids) do
    keys = Enum.map(ids, &key(sid, scope, &1))
    mget(sid, keys)
  end

  def stream(sid, scope) do
    match = key(sid, scope, "*")

    "0"
    |> Stream.unfold(fn
      :eof ->
        nil

      cursor ->
        case command(sid, ["SCAN", cursor, "MATCH", match, "COUNT", 1000]) do
          {:ok, ["0", keys]} -> {mget(sid, keys), :eof}
          {:ok, [next_cursor, keys]} -> {mget(sid, keys), next_cursor}
        end
    end)
    |> Stream.flat_map(fn users -> users end)
  end

  def put_many(_sid, _scope, []), do: :ok

  def put_many(sid, scope, entries) do
    data =
      Enum.map(entries, fn {id, data} ->
        [key(sid, scope, id), :erlang.term_to_binary(data)]
      end)

    args = List.flatten(data)

    case command(sid, ["MSET" | args]) do
      {:ok, _} ->
        keys = Enum.map(data, fn [k, _] -> k end)
        Expirer.expire(sid, keys)
        :ok

      {:error, err} ->
        {:error, err}
    end
  end

  defp mget(_sid, []), do: []

  defp mget(sid, keys) do
    case command(sid, ["MGET" | keys]) do
      {:ok, items} ->
        Enum.map(items, fn
          nil -> {:error, :not_found}
          val -> {:ok, :erlang.binary_to_term(val, [:safe])}
        end)

      {:error, err} ->
        [{:error, err}]
    end
  end

  defp key(sid, scope, id) do
    {scope, id} = Stash.key(scope, id)
    "#{sid}:#{scope}:#{id}"
  end

  def command(sid, cmd), do: Leader.command(sid, cmd)
end
