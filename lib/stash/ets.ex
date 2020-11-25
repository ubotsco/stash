defmodule Stash.ETS do
  defmodule Main do
    use GenServer

    defstruct [:ets, :opts]

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: name(opts))
    end

    def put(key, data, opts) do
      GenServer.call(name(opts), {:put, key, data})
    end

    ## Callbacks

    def init(opts) do
      ets = :ets.new(opts[:mod], [:set, :public, :named_table])
      {:ok, %__MODULE__{ets: ets, opts: opts}}
    end

    def handle_call({:put, key, data}, _from, state) do
      :ets.insert(state.ets, {key, data})
      {:reply, :ok, state}
    end

    ## Helpers

    def name(opts), do: :"#{opts[:mod]}.#{__MODULE__}"
  end

  @behaviour Stash.Stage

  def child_spec(opts) do
    %{
      id: Stash.ETS.Main.name(opts),
      start: {Stash.ETS.Main, :start_link, [opts]}
    }
  end

  def get(scope, id, opts) do
    mod = Keyword.fetch!(opts, :mod)
    key = {mod.scope(scope), id}

    case :ets.lookup(mod, key) do
      [] -> {:error, :not_found}
      [{^key, data}] -> {:ok, data}
    end
  end

  def put(scope, id, data, opts) do
    mod = Keyword.fetch!(opts, :mod)
    key = {mod.scope(scope), id}
    Main.put(key, data, opts)
  end

  def get_many(scope, ids, opts) do
    for id <- ids, do: get(scope, id, opts)
  end

  def put_many(scope, entries, opts) do
    mod = Keyword.fetch!(opts, :mod)
    sc = mod.scope(scope)

    for {id, data} <- entries do
      key = {sc, id}
      Main.put(key, data, opts)
    end

    :ok
  end
end
