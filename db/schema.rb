# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_06_29_071400) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "attempts", force: :cascade do |t|
    t.boolean "correct", default: false, null: false
    t.datetime "created_at", null: false
    t.string "from_language", null: false
    t.string "given"
    t.integer "term_id", null: false
    t.string "to_language", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["from_language", "to_language", "term_id"], name: "index_attempts_on_from_language_and_to_language_and_term_id"
    t.index ["term_id"], name: "index_attempts_on_term_id"
    t.index ["user_id"], name: "index_attempts_on_user_id"
  end

  create_table "decks", force: :cascade do |t|
    t.string "artist"
    t.datetime "created_at", null: false
    t.boolean "expanding", default: false, null: false
    t.string "listen_url"
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.string "status", default: "ready", null: false
    t.string "status_detail"
    t.string "topic"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "year"
    t.index ["user_id", "slug"], name: "index_decks_on_user_id_and_slug", unique: true
    t.index ["user_id"], name: "index_decks_on_user_id"
  end

  create_table "oauth_handoffs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "redeemed_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token"], name: "index_oauth_handoffs_on_token", unique: true
    t.index ["user_id"], name: "index_oauth_handoffs_on_user_id"
  end

  create_table "recordings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "language"
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_recordings_on_user_id"
  end

  create_table "schedulings", force: :cascade do |t|
    t.boolean "archived", default: false, null: false
    t.boolean "backfilled", default: false, null: false
    t.datetime "created_at", null: false
    t.float "difficulty", default: 0.0, null: false
    t.datetime "due"
    t.integer "ease", default: 3, null: false
    t.integer "elapsed_days", default: 0, null: false
    t.string "from_language", null: false
    t.integer "lapses", default: 0, null: false
    t.datetime "last_review"
    t.integer "reps", default: 0, null: false
    t.integer "scheduled_days", default: 0, null: false
    t.float "stability", default: 0.0, null: false
    t.integer "state", default: 0, null: false
    t.integer "term_id", null: false
    t.string "to_language", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["term_id"], name: "index_schedulings_on_term_id"
    t.index ["user_id", "due"], name: "index_schedulings_on_user_due"
    t.index ["user_id", "ease"], name: "index_schedulings_on_user_ease"
    t.index ["user_id", "term_id", "from_language", "to_language"], name: "index_schedulings_on_user_term_direction", unique: true
    t.index ["user_id"], name: "index_schedulings_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.string "api_token"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["api_token"], name: "index_sessions_on_api_token", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "deck_id", null: false
    t.string "key"
    t.string "kind", default: "word", null: false
    t.integer "position", default: 0, null: false
    t.boolean "reviewed", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["deck_id", "key"], name: "index_terms_on_deck_id_and_key", unique: true, where: "key IS NOT NULL"
    t.index ["deck_id"], name: "index_terms_on_deck_id"
    t.index ["kind"], name: "index_terms_on_kind"
  end

  create_table "translations", force: :cascade do |t|
    t.string "alternates"
    t.string "article"
    t.text "conjugation"
    t.datetime "created_at", null: false
    t.text "etymology"
    t.string "language", null: false
    t.text "mnemonic"
    t.text "phonetics"
    t.integer "term_id", null: false
    t.string "text", null: false
    t.datetime "updated_at", null: false
    t.index ["term_id", "language"], name: "index_translations_on_term_id_and_language", unique: true
    t.index ["term_id"], name: "index_translations_on_term_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "answer_mode", default: "type", null: false
    t.boolean "autoplay_prompt", default: true, null: false
    t.boolean "autoplay_wrong", default: false, null: false
    t.string "avatar_url"
    t.string "correct_feedback", default: "word", null: false
    t.datetime "created_at", null: false
    t.string "drill_direction", default: "forward"
    t.string "drill_order", default: "smart", null: false
    t.boolean "drill_recall_first", default: true, null: false
    t.boolean "drill_sentences", default: true, null: false
    t.string "email_address", null: false
    t.integer "flow_gap_next", default: 6, null: false
    t.integer "flow_gap_prompt", default: 3, null: false
    t.boolean "flow_mode", default: false, null: false
    t.boolean "flow_teach", default: true, null: false
    t.integer "generations_count", default: 0, null: false
    t.boolean "hide_mastered", default: true, null: false
    t.string "learning_languages"
    t.string "name"
    t.string "password_digest"
    t.string "provider"
    t.boolean "show_other_languages", default: false, null: false
    t.boolean "skip_easy", default: false, null: false
    t.string "source_language", default: "en", null: false
    t.string "target_language"
    t.string "uid"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "provider IS NOT NULL AND uid IS NOT NULL"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "attempts", "terms"
  add_foreign_key "attempts", "users"
  add_foreign_key "decks", "users"
  add_foreign_key "oauth_handoffs", "users"
  add_foreign_key "recordings", "users"
  add_foreign_key "schedulings", "terms"
  add_foreign_key "schedulings", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "terms", "decks"
  add_foreign_key "translations", "terms"
end
