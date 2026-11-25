defmodule Relay.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :username, :string
    field :display_name, :string
    field :bio, :string
    field :avatar_url, :string, default: "/images/default-avatar.png"
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, useful when displaying live validations.
      Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  @doc """
  A changeset for registering a user and their profile.
  """
  def registration_changeset(user, attrs, opts \\ []) do
    changeset =
      user
      |> cast(attrs, [:email, :username, :display_name, :bio, :avatar_url])
      |> validate_email(opts)

    changeset =
      if get_change(changeset, :username) || is_nil(get_field(changeset, :email)) do
        changeset
      else
        email = get_field(changeset, :email)
        put_change(changeset, :username, suggested_username(email))
      end

    changeset
    |> update_change(:username, &normalize_username/1)
    |> validate_username()
    |> validate_profile_fields()
  end

  @doc """
  A changeset for updating profile fields.
  """
  def profile_changeset(user, attrs) do
    changeset =
      user
      |> cast(attrs, [:username, :display_name, :bio, :avatar_url])
      |> update_change(:username, &normalize_username/1)
      |> validate_username()
      |> validate_profile_fields()

    if get_field(changeset, :avatar_url) in [nil, ""] do
      put_change(changeset, :avatar_url, "/images/default-avatar.png")
    else
      changeset
    end
  end

  defp validate_username(changeset) do
    changeset
    |> validate_required([:username])
    |> validate_length(:username, min: 3, max: 20)
    |> validate_format(:username, ~r/\A[a-z0-9_]+\z/,
      message: "can only contain lowercase letters, numbers, and underscores"
    )
    |> unsafe_validate_unique(:username, Relay.Repo)
    |> unique_constraint(:username)
  end

  defp validate_profile_fields(changeset) do
    changeset
    |> validate_length(:display_name, max: 50)
    |> validate_length(:bio, max: 160)
  end

  defp normalize_username(username) do
    username
    |> String.trim()
    |> String.downcase()
  end

  defp suggested_username(nil), do: "user"

  defp suggested_username(email) do
    local_part =
      email
      |> String.split("@")
      |> List.first()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_]/, "_")

    suffix =
      case Regex.run(~r/(\d+)$/, local_part) do
        [_, digits] -> String.slice(digits, -10, 10)
        _ -> nil
      end

    cond do
      suffix ->
        "user_" <> suffix

      byte_size(local_part) < 3 ->
        "user_" <> local_part

      true ->
        String.slice(local_part, 0, 20)
    end
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Relay.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for changing the password.

  It is important to validate the length of the password, as long passwords may
  be very expensive to hash for certain algorithms.

  ## Options

    * `:hash_password` - Hashes the password so it can be stored securely
      in the database and ensures the password field is cleared to prevent
      leaks in the logs. If password hashing is not needed and clearing the
      password field is not desired (like when using this changeset for
      validations on a LiveView form), this option can be set to `false`.
      Defaults to `true`.
  """
  def password_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:password])
    |> validate_confirmation(:password, message: "does not match password")
    |> validate_password(opts)
  end

  defp validate_password(changeset, opts) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, max: 72)
    # Examples of additional password validation:
    # |> validate_format(:password, ~r/[a-z]/, message: "at least one lower case character")
    # |> validate_format(:password, ~r/[A-Z]/, message: "at least one upper case character")
    # |> validate_format(:password, ~r/[!?@#$%^&*_0-9]/, message: "at least one digit or punctuation character")
    |> maybe_hash_password(opts)
  end

  defp maybe_hash_password(changeset, opts) do
    hash_password? = Keyword.get(opts, :hash_password, true)
    password = get_change(changeset, :password)

    if hash_password? && password && changeset.valid? do
      changeset
      # Hashing could be done with `Ecto.Changeset.prepare_changes/2`, but that
      # would keep the database transaction open longer and hurt performance.
      |> put_change(:hashed_password, Pbkdf2.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Pbkdf2.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Relay.Accounts.User{hashed_password: hashed_password}, password)
      when is_binary(hashed_password) and byte_size(password) > 0 do
    Pbkdf2.verify_pass(password, hashed_password)
  end

  def valid_password?(_, _) do
    Pbkdf2.no_user_verify()
    false
  end
end
