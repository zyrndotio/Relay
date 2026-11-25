defmodule Relay.Social do
  @moduledoc """
  Social graph operations for Relay.
  """

  import Ecto.Query, warn: false

  alias Relay.Accounts.User
  alias Relay.Repo
  alias Relay.Social.Follow

  @doc """
  Follows `followed` on behalf of `follower`.
  """
  def follow_user(%User{} = follower, %User{} = followed) do
    %Follow{}
    |> Follow.changeset(%{follower_id: follower.id, followed_id: followed.id})
    |> Repo.insert()
  end

  @doc """
  Stops `follower` from following `followed`. Safe to call more than once.
  """
  def unfollow_user(%User{} = follower, %User{} = followed) do
    Repo.delete_all(
      from follow in Follow,
        where:
          follow.follower_id == ^follower.id and
            follow.followed_id == ^followed.id
    )

    :ok
  end

  @doc """
  Returns whether `follower` follows `followed`.
  """
  def following?(%User{} = follower, %User{} = followed) do
    Repo.exists?(
      from follow in Follow,
        where:
          follow.follower_id == ^follower.id and
            follow.followed_id == ^followed.id
    )
  end

  @doc """
  Counts the followers of `user`.
  """
  def follower_count(%User{} = user) do
    Repo.aggregate(from(follow in Follow, where: follow.followed_id == ^user.id), :count)
  end

  @doc """
  Counts the users followed by `user`.
  """
  def following_count(%User{} = user) do
    Repo.aggregate(from(follow in Follow, where: follow.follower_id == ^user.id), :count)
  end
end
