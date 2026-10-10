CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS chat_users (
  user_id uuid PRIMARY KEY,
  full_name text NOT NULL DEFAULT '',
  username text,
  email text,
  google_photo_url text,
  interest text,
  auth_provider text NOT NULL DEFAULT 'local',
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS friendships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL,
  addressee_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending',
  message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (requester_id, addressee_id),
  CHECK (requester_id <> addressee_id),
  CHECK (status IN ('pending', 'accepted'))
);

CREATE INDEX IF NOT EXISTS idx_friendships_requester
  ON friendships (requester_id, status);

CREATE INDEX IF NOT EXISTS idx_friendships_addressee
  ON friendships (addressee_id, status);

CREATE TABLE IF NOT EXISTS chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sender_id uuid NOT NULL,
  receiver_id uuid NOT NULL,
  content_type text NOT NULL DEFAULT 'text',
  text text NOT NULL DEFAULT '',
  voice_data text,
  voice_mime_type text,
  voice_duration integer NOT NULL DEFAULT 0,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (content_type IN ('text', 'location', 'voice')),
  CHECK (sender_id <> receiver_id)
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_pair
  ON chat_messages (sender_id, receiver_id, created_at);

CREATE INDEX IF NOT EXISTS idx_chat_messages_receiver_unread
  ON chat_messages (receiver_id, read_at);
