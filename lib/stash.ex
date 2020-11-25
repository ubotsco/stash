defmodule Stash do
  defmacro __using__(opts) do
    stages = Keyword.fetch!(opts, :stages)

    quote do
      def stages, do: unquote(stages)
      def child_spec(opts), do: Stash.child_spec(__MODULE__, opts)
      def get(ctx, id), do: Stash.get(__MODULE__, ctx, id)
      def put(ctx, id, data), do: Stash.put(__MODULE__, ctx, id, data)
      def load(ctx, ids) when is_list(ids), do: Stash.load(__MODULE__, ctx, ids)
      def scope(s), do: to_string(s)

      defoverridable scope: 1
    end
  end

  def child_spec(mod, _opts) do
    children = stages(mod)

    %{
      id: mod,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one, name: mod]]}
    }
  end

  def get(mod, scope, id) do
    do_get(stages(mod), scope, id)
  end

  defp do_get([], _, _), do: {:error, :not_found}

  defp do_get([{stage, opts} | next], scope, id) do
    IO.inspect({:do_get, stage, id})

    case stage.get(scope, id, opts) do
      {:ok, data} ->
        {:ok, data}

      _error ->
        case do_get(next, scope, id) do
          {:ok, data} ->
            # Put data returned by lower levels
            stage.put(scope, id, data, opts)
            {:ok, data}

          error ->
            error
        end
    end
  end

  def put(mod, scope, id, data) do
    for {stage, opts} <- stages(mod), do: stage.put(scope, id, data, opts)
    :ok
  end

  def load(mod, scope, ids) do
    do_load(stages(mod), scope, ids)
  end

  defp do_load([], _scope, _ids), do: []
  defp do_load(_stages, _scope, []), do: []

  defp do_load([{stage, opts} | next], scope, ids) do
    IO.inspect({:do_load, stage, ids})

    # Fetch from current stage
    {hits, misses} =
      ids
      |> Enum.zip(stage.get_many(scope, ids, opts))
      |> Enum.split_with(&match?({_, {:ok, _}}, &1))

    # Fetch & save hits from next stage
    new = do_load(next, scope, Enum.map(misses, &elem(&1, 0)))
    stage.put_many(scope, new, opts)

    # Return both old & new hits
    Enum.map(hits, fn {id, {:ok, data}} -> {id, data} end) ++ new
  end

  defp stages(mod) do
    Enum.map(mod.stages, fn
      {stage, sopt} -> {stage, Keyword.put(sopt, :mod, mod)}
      stage -> {stage, [mod: mod]}
    end)
  end
end

defmodule Stash.Stage do
  @type scope :: binary
  @type id :: binary
  @type opts :: keyword
  @type data :: term

  @callback child_spec(opts) :: Supervisor.child_spec()
  @callback get(scope, id, opts) :: {:ok, data} | {:error, any}
  @callback put(scope, id, data :: term, opts) :: :ok | {:error, any}
  @callback get_many(scope, [id], opts) :: [{:ok, data} | {:error, any}]
  @callback put_many(scope, [{id, data}], opts) :: :ok | {:error, any}
end

defmodule Stash.Source do
  defmacro __using__(_) do
    quote do
      @behaviour Stash.Stage

      def child_spec(opts) do
        %{
          id: :"#{opts[:mod]}.#{__MODULE__}",
          start: {Agent, :start_link, [fn -> nil end]}
        }
      end

      def get_many(ctx, ids, opts), do: Enum.map(ids, &get(ctx, &1, opts))
      def put(_ctx, _id, _data, _opts), do: :ok
      def put_many(_ctx, _entries, _opts), do: :ok

      defoverridable get_many: 3
    end
  end
end
