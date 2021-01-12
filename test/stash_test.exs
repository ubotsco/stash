defmodule StashTest do
  use ExUnit.Case

  defmodule Context do
    defstruct [:team_id]
  end

  defmodule FakeStage do
    @behaviour Stash.Stage

    def start_link(sid, _opts \\ []), do: Agent.start_link(fn -> %{} end, name: sid)

    def child_spec(opts) do
      sid = Keyword.fetch!(opts, :sid)
      %{id: sid, start: {__MODULE__, :start_link, [sid, opts]}}
    end

    def get(sid, scope, id) do
      case Agent.get(sid, fn map -> Map.fetch(map, {scope, id}) end) do
        {:ok, hit} ->
          send(self(), {:get, sid, :hit, {scope, id}})
          {:ok, hit}

        :error ->
          send(self(), {:get, sid, :miss, {scope, id}})
          :error
      end
    end

    def put(sid, scope, id, data) do
      Agent.update(sid, fn map -> Map.put(map, {scope, id}, data) end)
      send(self(), {:put, sid, {scope, id}, data})
      :ok
    end

    def get_many(sid, scope, ids) do
      hits = Agent.get(sid, fn map -> Enum.map(ids, &Map.fetch(map, {scope, &1})) end)
      send(self(), {:get_many, sid, ids, hits})
      hits
    end

    def put_many(sid, scope, entries) do
      Agent.update(sid, fn map ->
        Enum.reduce(entries, map, fn {id, data}, map ->
          Map.put(map, {scope, id}, data)
        end)
      end)

      send(self(), {:put_many, sid, entries})
      :ok
    end
  end

  defmodule SimpleStash do
    use Stash,
      stages: [
        FakeStage,
        FakeStage,
        FakeStage
      ]

    def scope(ctx), do: ctx.team_id
  end

  @s0 :"#{SimpleStash}.0"
  @s1 :"#{SimpleStash}.1"
  @s2 :"#{SimpleStash}.2"

  setup do
    start_supervised!(SimpleStash)

    ctx = %Context{team_id: "TEAM1"}
    [ctx: ctx]
  end

  describe "supervision tree" do
    test "ensure correct processes & names" do
      assert Process.whereis(SimpleStash)
      assert %{active: 3} = Supervisor.count_children(SimpleStash)

      assert Process.whereis(@s0)
      assert Process.whereis(@s1)
      assert Process.whereis(@s2)

      refute Process.whereis(:"#{SimpleStash}.3")
    end
  end

  describe "get" do
    test "miss all stages", %{ctx: ctx} do
      assert {:error, :not_found} == SimpleStash.get(ctx, "x")
      assert_received {:get, @s0, :miss, _}
      assert_received {:get, @s1, :miss, _}
      assert_received {:get, @s2, :miss, _}
    end

    test "hit in first stage", %{ctx: ctx} do
      FakeStage.put(@s0, "TEAM1", "x", "hello")

      assert {:ok, "hello"} == SimpleStash.get(ctx, "x")
      assert_received {:get, @s0, :hit, _}

      refute_received {:get, @s1, _, _}
      refute_received {:get, @s2, _, _}
    end

    test "hit in second stage", %{ctx: ctx} do
      FakeStage.put(@s1, "TEAM1", "x", "hello")

      assert {:ok, "hello"} == SimpleStash.get(ctx, "x")
      assert_received {:get, @s0, :miss, _}
      assert_received {:get, @s1, :hit, _}
      assert_received {:put, @s0, _, _}

      refute_received {:get, @s2, _, _}
    end

    test "hit in last stage", %{ctx: ctx} do
      FakeStage.put(@s2, "TEAM1", "x", "hello")

      assert {:ok, "hello"} == SimpleStash.get(ctx, "x")
      assert_received {:get, @s0, :miss, _}
      assert_received {:get, @s1, :miss, _}
      assert_received {:get, @s2, :hit, _}
      assert_received {:put, @s1, _, _}
      assert_received {:put, @s0, _, _}
    end
  end

  describe "put" do
    test "put in all stages", %{ctx: ctx} do
      assert :ok == SimpleStash.put(ctx, "x", "hello")
      assert_received {:put, @s0, _, _}
      assert_received {:put, @s1, _, _}
      assert_received {:put, @s2, _, _}
    end
  end

  describe "load" do
    test "miss in all stages", %{ctx: ctx} do
      SimpleStash.load(ctx, ["x", "y", "z"])

      assert_received {:get_many, @s0, _, _}
      assert_received {:get_many, @s1, _, _}
      assert_received {:get_many, @s2, _, _}

      assert {:error, _} = SimpleStash.get(ctx, "x")
      assert {:error, _} = SimpleStash.get(ctx, "y")
      assert {:error, _} = SimpleStash.get(ctx, "z")
    end

    test "hit in last stage for one", %{ctx: ctx} do
      FakeStage.put(@s2, "TEAM1", "x", "hello")
      SimpleStash.load(ctx, ["x", "y", "z"])

      assert_received {:get_many, @s0, ["x", "y", "z"], _}
      assert_received {:get_many, @s1, ["x", "y", "z"], _}
      assert_received {:get_many, @s2, ["x", "y", "z"], _}

      assert_received {:put_many, @s1, [{"x", "hello"}]}
      assert_received {:put_many, @s0, [{"x", "hello"}]}

      assert {:ok, "hello"} = SimpleStash.get(ctx, "x")
      assert {:error, _} = SimpleStash.get(ctx, "y")
      assert {:error, _} = SimpleStash.get(ctx, "z")
    end

    test "hit one in each stage", %{ctx: ctx} do
      FakeStage.put(@s0, "TEAM1", "x", "hello")
      FakeStage.put(@s1, "TEAM1", "y", "world")
      FakeStage.put(@s2, "TEAM1", "z", "today")

      SimpleStash.load(ctx, ["x", "y", "z"])

      assert_received {:get_many, @s0, ["x", "y", "z"], _}
      assert_received {:get_many, @s1, ["y", "z"], _}
      assert_received {:get_many, @s2, ["z"], _}

      assert_received {:put_many, @s1, [{"z", "today"}]}
      assert_received {:put_many, @s0, [{"y", "world"}, {"z", "today"}]}

      flush()

      assert {:ok, "hello"} = SimpleStash.get(ctx, "x")
      assert {:ok, "world"} = SimpleStash.get(ctx, "y")
      assert {:ok, "today"} = SimpleStash.get(ctx, "z")

      assert_received {:get, @s0, :hit, {_, "x"}}
      assert_received {:get, @s0, :hit, {_, "y"}}
      assert_received {:get, @s0, :hit, {_, "z"}}
      refute_received {:get, @s1, _, _}
      refute_received {:get, @s2, _, _}
    end
  end

  def flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end
