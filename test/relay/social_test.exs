defmodule Relay.SocialTest do
  use Relay.DataCase

  alias Relay.Social

  import Relay.AccountsFixtures

  describe "follows" do
    test "follows and unfollows another user while maintaining counts" do
      follower = user_fixture()
      followed = user_fixture()

      assert {:ok, _follow} = Social.follow_user(follower, followed)
      assert Social.following?(follower, followed)
      assert Social.follower_count(followed) == 1
      assert Social.following_count(follower) == 1

      assert :ok = Social.unfollow_user(follower, followed)
      refute Social.following?(follower, followed)
      assert Social.follower_count(followed) == 0
      assert Social.following_count(follower) == 0
      assert :ok = Social.unfollow_user(follower, followed)
    end

    test "rejects duplicate and self follows" do
      user = user_fixture()
      followed = user_fixture()

      assert {:ok, _follow} = Social.follow_user(user, followed)
      assert {:error, changeset} = Social.follow_user(user, followed)
      assert "has already been taken" in errors_on(changeset).follower_id

      assert {:error, self_follow_changeset} = Social.follow_user(user, user)
      assert "cannot follow yourself" in errors_on(self_follow_changeset).followed_id
    end
  end
end
