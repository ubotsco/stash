defmodule Stash do
  defmacro __using__(opts) do
    stages = Keyword.fetch!(opts, :stages)

    quote do
      def stages, do: unquote(stages)
      def start_link, do: Stash.start_link(__MODULE__)
      def child_spec(opts), do: Stash.child_spec(__MODULE__, opts)
      def get(ctx, id), do: Stash.get(__MODULE__, ctx, id)
      def put(ctx, id, data, opts \\ []), do: Stash.put(__MODULE__, ctx, id, data, opts)
      def put_many(ctx, entries, opts \\ []), do: Stash.put_many(__MODULE__, ctx, entries, opts)
      def delete(ctx, id), do: Stash.delete(__MODULE__, ctx, id)
      def delete_all(ctx), do: Stash.delete_all(__MODULE__, ctx)
      def load(ctx, ids) when is_list(ids), do: Stash.load(__MODULE__, ctx, ids)
      def stream(ctx, from: from), do: Stash.stream(__MODULE__, ctx, from)
      def clear_all(), do: Stash.clear_all(__MODULE__)
      def scope(s), do: to_string(s)

      defoverridable scope: 1
    end
  end

  def sid(mod, name), do: :"#{mod}.#{name}"

  def key({scope, _}, id), do: {scope, id}
  def key(scope, id), do: {scope, id}

  def start_link(mod) do
    children =
      Enum.map(mod.stages(), fn
        {name, {stage, opts}} -> {stage, Keyword.put(opts, :sid, sid(mod, name))}
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
            stage.put(sid, scope, id, data, [])
            {:ok, data}

          error ->
            error
        end
    end
  end

  def put(mod, scope, id, data, opts) do
    scope = mod.scope(scope)
    for {stage, sid} <- stages(mod), do: stage.put(sid, scope, id, data, opts)
    :ok
  end

  def put_many(mod, scope, entries, opts) do
    scope = mod.scope(scope)
    for {stage, sid} <- stages(mod), do: stage.put_many(sid, scope, entries, opts)
    :ok
  end

  def delete(mod, scope, id) do
    scope = mod.scope(scope)
    for {stage, sid} <- stages(mod), do: stage.delete(sid, scope, id)
    :ok
  end

  def delete_all(mod, scope) do
    scope = mod.scope(scope)
    for {stage, sid} <- stages(mod), do: stage.delete_all(sid, scope)
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
    stage.put_many(sid, scope, new, [])

    # Return both old & new hits
    Enum.map(hits, fn {id, {:ok, data}} -> {id, data} end) ++ new
  end

  defp stages(mod) do
    Enum.map(mod.stages(), fn
      {name, {stage, _}} -> {stage, sid(mod, name)}
    end)
  end

  def stream(mod, scope, from) do
    {stage, _} = Keyword.fetch!(mod.stages(), from)
    stage.stream(sid(mod, from), mod.scope(scope))
  end

  def clear_all(mod) do
    for {stage, sid} <- stages(mod), do: :ok = stage.clear_all(sid)
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
  @callback put(sid, scope, id, data :: term, opts :: keyword) :: :ok | {:error, any}
  @callback get_many(sid, scope, [id]) :: [{:ok, data} | {:error, any}]
  @callback put_many(sid, scope, [{id, data}], opts :: keyword) :: :ok | {:error, any}
  @callback clear_all(sid) :: :ok | {:error, any}
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
      def put(_sid, _scope, _id, _data, _opts), do: :ok
      def put_many(_sid, _scope, _entries, _opts), do: :ok
      def delete(_sid, _scope, _id), do: :ok
      def delete_all(_sid, _scope), do: :ok
      def clear_all(_sid), do: :ok

      defoverridable get_many: 3
    end
  end
end
