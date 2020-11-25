defmodule StashTest do
  use ExUnit.Case
  doctest Stash

  test "greets the world" do
    assert Stash.hello() == :world
  end
end
