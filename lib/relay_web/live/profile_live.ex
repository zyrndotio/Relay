defmodule RelayWeb.ProfileLive do
  use RelayWeb, :live_view

  alias Relay.Accounts
  alias Relay.Accounts.Scope
  alias Relay.Social

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <main class="mx-auto max-w-2xl px-4 py-10">
        <%= if @profile do %>
          <section class="overflow-hidden rounded-3xl border border-base-300 bg-base-100 shadow-sm">
            <div class="h-36 bg-gradient-to-br from-primary/20 via-base-200 to-secondary/20" />
            <div class="px-6 pb-7">
              <div class="-mt-14 flex items-end justify-between gap-4">
                <img
                  src={@profile.avatar_url || "/images/default-avatar.png"}
                  alt={"#{@profile.display_name || @profile.username}'s avatar"}
                  class="h-28 w-28 rounded-full border-4 border-base-100 bg-base-200 object-cover"
                />
                <%= cond do %>
                  <% @own_profile? -> %>
                    <.link
                      navigate={~p"/users/settings"}
                      class="rounded-full border border-base-300 px-5 py-2 text-sm font-semibold transition hover:bg-base-200"
                    >
                      Edit profile
                    </.link>
                  <% @current_scope.user -> %>
                    <button
                      id="follow_button"
                      type="button"
                      phx-click={if @following?, do: "unfollow", else: "follow"}
                      class={[
                        "rounded-full px-5 py-2 text-sm font-semibold transition",
                        if(@following?,
                          do: "border border-base-300 hover:border-error hover:text-error",
                          else: "bg-primary text-primary-content hover:brightness-110"
                        )
                      ]}
                    >
                      {if @following?, do: "Following", else: "Follow"}
                    </button>
                  <% true -> %>
                    <.link
                      navigate={~p"/users/log-in"}
                      class="rounded-full bg-primary px-5 py-2 text-sm font-semibold text-primary-content transition hover:brightness-110"
                    >
                      Log in to follow
                    </.link>
                <% end %>
              </div>

              <div class="mt-5">
                <h1 class="text-2xl font-bold tracking-tight">
                  {@profile.display_name || @profile.username}
                </h1>

                <p class="mt-1 text-sm text-base-content/60">@{@profile.username}</p>

                <p :if={@profile.bio not in [nil, ""]} class="mt-4 whitespace-pre-wrap text-base">
                  {@profile.bio}
                </p>
              </div>

              <div class="mt-5 flex gap-5 text-sm">
                <p>
                  <strong class="font-bold">{@following_count}</strong>
                  <span class="text-base-content/60"> Following</span>
                </p>

                <p>
                  <strong class="font-bold">{@follower_count}</strong>
                  <span class="text-base-content/60"> Followers</span>
                </p>
              </div>
            </div>
          </section>

          <nav aria-label="Profile sections" class="mt-5 grid grid-cols-3 border-b border-base-300">
            <a href="#posts" class="border-b-2 border-primary py-4 text-center text-sm font-semibold">
              Posts
            </a>

            <a href="#replies" class="py-4 text-center text-sm font-medium text-base-content/60">
              Replies
            </a>

            <a href="#likes" class="py-4 text-center text-sm font-medium text-base-content/60">
              Likes
            </a>
          </nav>

          <div id="posts" class="py-10 text-center text-sm text-base-content/50">
            No posts yet
          </div>
        <% else %>
          <section class="rounded-3xl border border-base-300 bg-base-100 px-6 py-16 text-center">
            <h1 class="text-2xl font-bold">Profile not found</h1>

            <p class="mt-2 text-base-content/60">This account may have changed its username.</p>
          </section>
        <% end %>
      </main>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    profile = Accounts.get_user_by_username(username)
    viewer = current_user(socket)
    own_profile? = viewer && profile && viewer.id == profile.id

    socket =
      socket
      |> assign(:current_scope, socket.assigns.current_scope || %Scope{})
      |> assign(:profile, profile)
      |> assign(:own_profile?, own_profile?)
      |> assign(
        :following?,
        viewer && profile && !own_profile? && Social.following?(viewer, profile)
      )
      |> assign(:follower_count, profile && Social.follower_count(profile))
      |> assign(:following_count, profile && Social.following_count(profile))

    {:ok, socket}
  end

  @impl true
  def handle_event("follow", _params, socket) do
    change_follow(socket, :follow)
  end

  def handle_event("unfollow", _params, socket) do
    change_follow(socket, :unfollow)
  end

  defp change_follow(socket, action) do
    cond do
      is_nil(current_user(socket)) ->
        {:noreply, put_flash(socket, :error, "Log in to follow this account.")}

      is_nil(socket.assigns.profile) ->
        {:noreply, put_flash(socket, :error, "Profile not found.")}

      true ->
        update_follow(socket, action)
    end
  end

  defp update_follow(socket, action) do
    follower = current_user(socket)
    followed = socket.assigns.profile

    result =
      case action do
        :follow -> Social.follow_user(follower, followed)
        :unfollow -> Social.unfollow_user(follower, followed)
      end

    case result do
      {:ok, _follow} ->
        {:noreply, refresh_follow_data(socket)}

      :ok ->
        {:noreply, refresh_follow_data(socket)}

      {:error, _changeset} ->
        {:noreply,
         socket
         |> refresh_follow_data()
         |> put_flash(:error, "Could not update follow status. Please try again.")}
    end
  end

  defp refresh_follow_data(socket) do
    follower = current_user(socket)
    followed = socket.assigns.profile

    socket
    |> assign(:following?, Social.following?(follower, followed))
    |> assign(:follower_count, Social.follower_count(followed))
    |> assign(:following_count, Social.following_count(followed))
  end

  defp current_user(socket) do
    case socket.assigns.current_scope do
      %{user: user} -> user
      nil -> nil
    end
  end
end
