defmodule RelayWeb.ProfileLiveTest do
  use RelayWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Relay.AccountsFixtures

  alias Relay.Social

  describe "public profile" do
    test "renders profile details and lets a signed-in viewer follow and unfollow", %{conn: conn} do
      profile =
        user_fixture(%{
          username: "relay_profile",
          display_name: "Relay Profile",
          bio: "A short profile bio",
          avatar_url: "/avatars/relay.png"
        })

      viewer = user_fixture()

      {:ok, view, _html} =
        conn
        |> log_in_user(viewer)
        |> live(~p"/@relay_profile")

      assert has_element?(view, "h1", "Relay Profile")
      assert has_element?(view, "img[src='/avatars/relay.png']")
      assert has_element?(view, "p", "@relay_profile")
      assert has_element?(view, "p", "A short profile bio")
      assert has_element?(view, "#follow_button", "Follow")
      assert has_element?(view, "strong", "0")

      view
      |> element("#follow_button")
      |> render_click()

      assert has_element?(view, "#follow_button", "Following")
      assert Social.following?(viewer, profile)
      assert has_element?(view, "strong", "1")

      view
      |> element("#follow_button")
      |> render_click()

      assert has_element?(view, "#follow_button", "Follow")
      refute Social.following?(viewer, profile)
      assert has_element?(view, "strong", "0")
    end

    test "hides follow controls on the viewer's own profile", %{conn: conn} do
      user = user_fixture(%{username: "my_profile"})

      {:ok, view, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/@my_profile")

      assert has_element?(view, "a", "Edit profile")
      refute has_element?(view, "#follow_button")
    end

    test "allows guests to view profiles and directs them to log in to follow", %{conn: conn} do
      user = user_fixture(%{username: "guest_profile"})

      {:ok, view, _html} = live(conn, ~p"/@guest_profile")

      assert has_element?(view, "h1", user.username)
      assert has_element?(view, "a", "Log in to follow")
    end
  end
end
