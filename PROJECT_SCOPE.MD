# Relay — Project Architecture & Agent Instructions

## 1. Project Overview
**Relay** is a real-time social media web application (X.com clone) built as a portfolio project.
- **Stack:** Elixir 1.20 / Erlang OTP 29, Phoenix 1.8 (LiveView), Ecto + PostgreSQL, Tailwind CSS v4 + daisyUI 5, Heroicons.
- **Architecture Rule:** Keep this a 100% Elixir/Phoenix monolith. Do NOT introduce React, Vue, Redis, Kafka, or external message brokers. Use Phoenix's built-in primitives (`Phoenix.PubSub`, `Phoenix.Presence`, `LiveView Streams`, `allow_upload/3`).
- **Base Conventions:** Always obey the framework rules in `AGENTS.md` (Phoenix 1.8 conventions, `<.input>`, `<Layouts.app>`, LiveView Streams).

---

## 2. Core Data Model (PostgreSQL)

### `Accounts` Context (`Relay.Accounts`)
Extend the generated `users` table and `Relay.Accounts.User` schema with:
- `username` (`:string`, `null: false`, unique index, lowercase alphanumeric + underscores, 3–20 chars)
- `display_name` (`:string`)
- `bio` (`:text`, max 160 chars)
- `avatar_url` (`:string`, default placeholder if nil)

### `Social` Context (`Relay.Social`)
- **`follows`**: `follower_id` (`references(:users)`), `followed_id` (`references(:users)`), unique index on `[:follower_id, :followed_id]`.
- **`posts`**:
  - `user_id` (`references(:users)`, `null: false`)
  - `body` (`:text`, max 280 chars — optional if `media_urls` is non-empty)
  - `media_urls` (`{:array, :string}`, default `[]`)
  - `parent_id` (`references(:posts)` — nullable, for threaded replies)
  - `repost_of_id` (`references(:posts)` — nullable, for reposts/quote posts)
  - `likes_count` (`:integer`, default `0`)
  - `reposts_count` (`:integer`, default `0`)
  - `replies_count` (`:integer`, default `0`)
- **`likes`**: `user_id` (`references(:users)`), `post_id` (`references(:posts)`), unique index on `[:user_id, :post_id]`.

### `Chat` Context (`Relay.Chat`)
- **`conversations`**: `id`, `timestamps()`
- **`conversation_members`**: `conversation_id` (`references(:conversations)`), `user_id` (`references(:users)`), `last_read_at` (`:utc_datetime`), unique index on `[:conversation_id, :user_id]`.
- **`messages`**:
  - `conversation_id` (`references(:conversations)`, `null: false`)
  - `sender_id` (`references(:users)`, `null: false`)
  - `body` (`:text`, `null: false`)
  - `media_url` (`:string`, nullable)

---

## 3. Feature Specifications

### Feature 1: Profiles & Follows
- Public profile route: `/@:username` (`ProfileLive`) showing display name, `@handle`, bio, follower/following counts, Follow/Unfollow button, and tabbed streams (Posts, Replies, Likes).
- Profile settings updates in `/users/settings` for `display_name`, `username`, `bio`, and avatar upload.

### Feature 2: Real-Time Timeline & Engagement (`HomeLive` at `/`)
- **UI Layout:** X-inspired 3-column responsive layout (Left sidebar navigation, Center scrolling feed, Right sidebar with user search & suggested accounts) styled with Tailwind + daisyUI dark/light support.
- **Feed Tabs:** `"For You"` (algorithmic ranking) and `"Following"` (chronological posts from followed users).
- **LiveView Streams:** Render feed posts using `stream(socket, :posts, posts)` with `phx-update="stream"`. Never hold large post lists in regular socket assigns.
- **Real-Time PubSub:** Broadcast `{:post_created, post}`, `{:post_liked, post}`, and `{:post_deleted, post}` over `Phoenix.PubSub` (`"timeline:public"` and user topics) so open clients update counts and prepend new posts live.

### Feature 3: Media Uploads
- Use LiveView `allow_upload/3` (`accept: ~w(.jpg .jpeg .png .gif .webp .mp4)`, `max_entries: 4`, `max_file_size: 15_000_000`).
- Store uploaded files in `priv/static/uploads` via `consume_uploaded_entries/3` (designed cleanly behind a `Relay.Storage` module so S3/Cloudflare R2 can be swapped in later).

### Feature 4: Direct Messaging (`MessagesLive` at `/messages` and `/messages/:id`)
- Split-pane inbox view: conversation list on the left, active message thread on the right.
- Subscribe active threads to `"conversation:#{conversation.id}"` via `Phoenix.PubSub` for instant message delivery.
- Track online status and `"User is typing..."` state using `Phoenix.Presence`.

### Feature 5: Algorithmic "For You" Ranking
- Implement `Relay.Social.list_for_you_posts(user, opts)` using a weighted PostgreSQL query combining:
  1. Engagement score: `(likes_count * 2) + (reposts_count * 3) + (replies_count * 4)`
  2. Affinity boost: bonus weight if `post.user_id` is followed by `current_user`
  3. Time-decay gravity: divide score by `(hours_since_posted + 2) ^ 1.5` so fresh posts rise and older posts decay naturally.

---

## 4. Development Workflow Rules for AI Agents
1. **Build incrementally:** Complete one vertical slice (migration → schema → context functions → LiveView UI → tests) before starting the next.
2. **Verify everything:** Run `mix ecto.migrate` and `mix test` after every feature slice and fix any compiler warnings or test failures immediately.
3. **Database integrity:** Use `Ecto.Multi` or atomic `Repo.update_all(..., inc: [likes_count: 1])` when toggling likes/reposts so counter caches never drift out of sync.
