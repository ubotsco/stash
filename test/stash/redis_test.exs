defmodule Stash.RedisTest do
  use ExUnit.Case

  setup tags do
    sid = :"#{tags.describe}_#{tags.test}"
    start_supervised!({Stash.Redis, [sid: sid, redis_url: "redis://localhost:6379/3"]})
    {:ok, sid: sid}
  end

  defmodule User do
    defstruct [:id, :name]
  end

  describe "put/4" do
    test "it saves simple value in Redis", %{sid: sid} do
      assert :ok = Stash.Redis.put(sid, "users", "u1", "Hodor")
      assert {:ok, data} = Stash.Redis.get(sid, "users", "u1")
      assert data == "Hodor"
    end

    test "it saves complex value in Redis", %{sid: sid} do
      user = %User{id: 1, name: "Hodor"}

      assert :ok = Stash.Redis.put(sid, "users", "u1", user)
      assert {:ok, user} == Stash.Redis.get(sid, "users", "u1")
    end

    # test "it doesn't set TTL if not provided"
    # test "it sets TTL if provided"
    # test "it overwrites value and its TTL"
  end

  describe "get/3" do
    test "it returns nil if saved value is nil", %{sid: sid} do
      assert :ok = Stash.Redis.put(sid, "users", "u1", nil)
      assert {:ok, nil} == Stash.Redis.get(sid, "users", "u1")
    end

    test "it returns {:error, :not_found} if key doesn't exist", %{sid: sid} do
      assert {:error, :not_found} == Stash.Redis.get(sid, "users", "u404")
    end

    # test "it returns error if TTL expired"
  end

  describe "put_many/3" do
    test "it handles empty list", %{sid: sid} do
      assert :ok == Stash.Redis.put_many(sid, "users", [])
    end

    test "it saves multiple entries", %{sid: sid} do
      assert :ok ==
               Stash.Redis.put_many(sid, "users", [
                 {"u1", "Alice"},
                 {"u2", "Bob"}
               ])

      assert {:ok, "Alice"} == Stash.Redis.get(sid, "users", "u1")
      assert {:ok, "Bob"} == Stash.Redis.get(sid, "users", "u2")
    end
  end

  describe "get_many/3" do
    test "it handles empty list", %{sid: sid} do
      assert [] = Stash.Redis.get_many(sid, "users", [])
    end

    test "it keeps the order", %{sid: sid} do
      :ok = Stash.Redis.put(sid, "users", "a", "Alice")
      :ok = Stash.Redis.put(sid, "users", "c", "Charlie")
      :ok = Stash.Redis.put(sid, "users", "b", "Bob")

      assert [
               {:ok, "Alice"},
               {:ok, "Bob"},
               {:ok, "Charlie"}
             ] = Stash.Redis.get_many(sid, "users", ["a", "b", "c"])
    end

    test "it handles missing values", %{sid: sid} do
      :ok = Stash.Redis.put(sid, "users", "a", "Alice")
      :ok = Stash.Redis.put(sid, "users", "c", "Charlie")

      assert [
               {:ok, "Alice"},
               {:error, :not_found},
               {:ok, "Charlie"}
             ] = Stash.Redis.get_many(sid, "users", ["a", "b", "c"])
    end
  end

  describe "stream/2" do
    test "empty steam", %{sid: sid} do
      stream = Stash.Redis.stream(sid, "empty")
      assert Enum.count(stream) == 0
    end

    test "small stream", %{sid: sid} do
      :ok = Stash.Redis.put(sid, "small", "a", "Alice")
      :ok = Stash.Redis.put(sid, "small", "b", "Bob")
      :ok = Stash.Redis.put(sid, "small", "c", "Charlie")
      stream = Stash.Redis.stream(sid, "small")
      assert Enum.count(stream) == 3
    end

    test "big stream", %{sid: sid} do
      for i <- 1..5 do
        entries = Enum.map(1..100, fn j -> {"#{i}-#{j}", "Alice"} end)
        :ok = Stash.Redis.put_many(sid, "big", entries)
      end

      stream = Stash.Redis.stream(sid, "big")
      assert Enum.count(stream) == 500
    end
  end

  # describe "clear_all!" do
  #   test "it clears all cachens keys" do
  #   test "it works when called on empty collection" do
  # end
end
