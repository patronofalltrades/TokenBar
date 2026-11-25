-- Class leaderboard table (TRD Section 17.5). The server keeps no IP address and no other field.
CREATE TABLE IF NOT EXISTS members (
  class_code              TEXT    NOT NULL,
  handle_key              TEXT    NOT NULL,  -- the handle in lower case
  handle                  TEXT    NOT NULL,  -- the handle as the member wrote it first
  token_hash              TEXT    NOT NULL,  -- SHA-256 of the member token, in hex
  as_of                   TEXT    NOT NULL,
  week_cost_eur           REAL    NOT NULL,
  week_output_tokens      INTEGER NOT NULL,
  spend_since_install_eur REAL    NOT NULL,
  updated_at              INTEGER NOT NULL,  -- milliseconds since 1970
  PRIMARY KEY (class_code, handle_key)
);
