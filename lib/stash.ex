defmodule Stash do
  defmacro __using__(opts) do
    stages = Keyword.fetch!(opts, :stages)

    quote do
      def stages, do: unquote(stages)
      def start_link, do: Stash.start_link(__MODULE__)
      def child_spec(opts), do: Stash.child_spec(__MODULE__, opts)
      def get(ctx, id), do: Stash.get(__MODULE__, ctx, id)
      def put(ctx, id, data), do: Stash.put(__MODULE__, ctx, id, data)
      def put_many(ctx, entries), do: Stash.put_many(__MODULE__, ctx, entries)
      def load(ctx, ids) when is_list(ids), do: Stash.load(__MODULE__, ctx, ids)
      def scope(s), do: to_string(s)

      defoverridable scope: 1
    end
  end

  defp sid(mod, index), do: :"#{mod}.#{index}"

  def key({scope, _}, id), do: {scope, id}
  def key(scope, id), do: {scope, id}

  def start_link(mod) do
    children =
      mod.stages
      |> Enum.with_index()
      |> Enum.map(fn
        {{stage, opts}, idx} -> {stage, Keyword.put(opts, :sid, sid(mod, idx))}
        {stage, idx} -> {stage, sid: sid(mod, idx)}
      end)

    Supervisor.start_link(children, strategy: :one_for_one, name: mod)
  end

  def child_spec(mod, _opts) do
    %{
      id: mod,
      type: :supervisor,
      start: {__MODULE__, :start_link, [mod]}
    }
  end

  def get(mod, scope, id) do
    do_get(stages(mod), mod.scope(scope), id)
  end

  defp do_get([], _, _), do: {:error, :not_found}

  defp do_get([{stage, sid} | next], scope, id) do
    case stage.get(sid, scope, id) do
      {:ok, data} ->
        {:ok, data}

      _error ->
        case do_get(next, scope, id) do
          {:ok, data} ->
            # Put data returned by lower levels
            stage.put(sid, scope, id, data)
            {:ok, data}

          error ->
            error
        end
    end
  end

  def put(mod, scope, id, data) do
    scope = mod.scope(scope)
    for {stage, sid} <- stages(mod), do: stage.put(sid, scope, id, data)
    :ok
  end

  def put_many(mod, scope, entries) do
    scope = mod.scope(scope)
    for {stage, sid} <- stages(mod), do: stage.put_many(sid, scope, entries)
    :ok
  end

  def load(mod, scope, ids) do
    do_load(stages(mod), mod.scope(scope), ids)
  end

  defp do_load([], _scope, _ids), do: []
  defp do_load(_stages, _scope, []), do: []

  defp do_load([{stage, sid} | next], scope, ids) do
    # Fetch from current stage
    {hits, misses} =
      ids
      |> Enum.zip(stage.get_many(sid, scope, ids))
      |> Enum.split_with(&match?({_, {:ok, _}}, &1))

    # Fetch & save hits from next stage
    new = do_load(next, scope, Enum.map(misses, &elem(&1, 0)))
    stage.put_many(sid, scope, new)

    # Return both old & new hits
    Enum.map(hits, fn {id, {:ok, data}} -> {id, data} end) ++ new
  end

  defp stages(mod) do
    mod.stages
    |> Enum.with_index()
    |> Enum.map(fn
      {{stage, _}, idx} -> {stage, sid(mod, idx)}
      {stage, idx} -> {stage, sid(mod, idx)}
    end)
  end

  def stream(mod, scope, index \\ 0) do
    {stage, sid} = Enum.at(stages(mod), index)
    stage.stream(sid, mod.scope(scope))
  end
end

defmodule Stash.Stage do
  @type sid :: atom
  @type scope :: binary | {binary, any}
  @type id :: binary
  @type opts :: keyword
  @type data :: term

  @callback child_spec(opts) :: Supervisor.child_spec()
  @callback get(sid, scope, id) :: {:ok, data} | {:error, any}
  @callback put(sid, scope, id, data :: term) :: :ok | {:error, any}
  @callback get_many(sid, scope, [id]) :: [{:ok, data} | {:error, any}]
  @callback put_many(sid, scope, [{id, data}]) :: :ok | {:error, any}
end

defmodule Stash.Source do
  defmacro __using__(_) do
    quote do
      @behaviour Stash.Stage

      def child_spec(opts) do
        sid = Keyword.fetch!(opts, :sid)
        %{id: sid, start: {Agent, :start_link, [fn -> sid end]}}
      end

      def get_many(sid, scope, ids), do: Enum.map(ids, &get(sid, scope, &1))
      def put(_sid, _scope, _id, _data), do: :ok
      def put_many(_sid, _scope, _entries), do: :ok

      defoverridable get_many: 3
    end
  end
end
