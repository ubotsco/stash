defmodule Stash.ETSTest do
  use ExUnit.Case

  setup tags do
    sid = :"#{tags.describe}_#{tags.test}"
    start_supervised!({Stash.ETS, [sid: sid]})
    {:ok, sid: sid}
  end

  defmodule User do
    defstruct [:id, :name]
  end

  describe "put/4" do
    test "it saves simple value", %{sid: sid} do
      assert :ok = Stash.ETS.put(sid, "users", "u1", "Hodor", [])
      assert {:ok, data} = Stash.ETS.get(sid, "users", "u1")
      assert data == "Hodor"
    end

    test "it saves complex value", %{sid: sid} do
      user = %User{id: 1, name: "Hodor"}

      assert :ok = Stash.ETS.put(sid, "users", "u1", user, [])
      assert {:ok, user} == Stash.ETS.get(sid, "users", "u1")
    end

    # test "it doesn't set TTL if not provided"
    # test "it sets TTL if provided"
    # test "it overwrites value and its TTL"
  end

  describe "get/3" do
    # test "it returns nil if saved value is nil", %{sid: sid} do
    #   assert :ok = Stash.ETS.put(sid, "users", "u1", nil, [])
    #   assert {:ok, nil} == Stash.ETS.get(sid, "users", "u1")
    # end

    test "it returns {:error, :not_found} if key doesn't exist", %{sid: sid} do
      assert {:error, :not_found} == Stash.ETS.get(sid, "users", "u404")
    end

    # test "it returns nil if TTL expired"
  end

  describe "put_many/3" do
    test "it handles empty list", %{sid: sid} do
      assert :ok == Stash.ETS.put_many(sid, "users", [], [])
    end

    test "it saves multiple entries", %{sid: sid} do
      assert :ok ==
               Stash.ETS.put_many(
                 sid,
                 "users",
                 [
                   {"u1", "Alice"},
                   {"u2", "Bob"}
                 ],
                 []
               )

      assert {:ok, "Alice"} == Stash.ETS.get(sid, "users", "u1")
      assert {:ok, "Bob"} == Stash.ETS.get(sid, "users", "u2")
    end
  end

  describe "get_many/3" do
    test "it handles empty list", %{sid: sid} do
      assert [] = Stash.ETS.get_many(sid, "users", [])
    end

    test "it keeps the order", %{sid: sid} do
      :ok = Stash.ETS.put(sid, "users", "a", "Alice", [])
      :ok = Stash.ETS.put(sid, "users", "c", "Charlie", [])
      :ok = Stash.ETS.put(sid, "users", "b", "Bob", [])

      assert [
               {:ok, "Alice"},
               {:ok, "Bob"},
               {:ok, "Charlie"}
             ] = Stash.ETS.get_many(sid, "users", ["a", "b", "c"])
    end

    test "it handles missing values", %{sid: sid} do
      :ok = Stash.ETS.put(sid, "users", "a", "Alice", [])
      :ok = Stash.ETS.put(sid, "users", "c", "Charlie", [])

      assert [
               {:ok, "Alice"},
               {:error, :not_found},
               {:ok, "Charlie"}
             ] = Stash.ETS.get_many(sid, "users", ["a", "b", "c"])
    end
  end

  # describe "clear_all!" do
  #   test "it clears all cache keys"
  #   test "it works when called on empty collection"
  # end
end
