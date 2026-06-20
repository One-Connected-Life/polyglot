# FSRS scheduling cache — one row per (user, term, direction).
#
# This is a derived cache: the authoritative source is still the `attempts`
# table (the immutable event log). Scheduling rows are BUILT by replaying
# attempts chronologically through FsrsScheduler#replay and are UPDATED
# incrementally on each new attempt when the FSRS_ENABLED flag is on.
#
# Columns mirror Fsrs::Card#to_h (FsrsScheduler::CARD_KEYS) so round-tripping
# is lossless. `ease` (1–5) is our addition: AI-prefilled, user-adjustable,
# fed into FSRS as the initial difficulty signal.
#
# Guard: backfilled = true once the replay has run for this row. Until then,
# the row doesn't exist (nil from find_by is the "not backfilled yet" signal).
class CreateSchedulings < ActiveRecord::Migration[8.1]
  def change
    create_table :schedulings do |t|
      t.references :user,                null: false, foreign_key: true
      t.references :term,                null: false, foreign_key: true
      t.string     :from_language,       null: false
      t.string     :to_language,         null: false

      # FSRS::Card columns (see FsrsScheduler::CARD_KEYS)
      t.integer    :state,               null: false, default: 0  # Fsrs::State::NEW
      t.datetime   :due,                 null: true
      t.float      :stability,           null: false, default: 0.0
      t.float      :difficulty,          null: false, default: 0.0
      t.integer    :elapsed_days,        null: false, default: 0
      t.integer    :scheduled_days,      null: false, default: 0
      t.integer    :reps,                null: false, default: 0
      t.integer    :lapses,              null: false, default: 0
      t.datetime   :last_review,         null: true

      # Our addition: 1–5 ease (AI-prefilled, user-adjustable).
      # English cognates start at 1 (trivial → auto-skipped from rotation).
      # Higher = harder for this learner (more Romance-language cross-over = lower).
      t.integer    :ease,                null: false, default: 3

      # True once the replay backfill has run for this (user, term, direction).
      t.boolean    :backfilled,          null: false, default: false

      # True once the word has been permanently archived ("done forever").
      t.boolean    :archived,            null: false, default: false

      t.timestamps
    end

    add_index :schedulings, [:user_id, :term_id, :from_language, :to_language],
              unique: true, name: "index_schedulings_on_user_term_direction"
    add_index :schedulings, [:user_id, :due], name: "index_schedulings_on_user_due"
    add_index :schedulings, [:user_id, :ease], name: "index_schedulings_on_user_ease"
  end
end
