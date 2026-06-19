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

ActiveRecord::Schema[8.1].define(version: 2026_06_19_193000) do
  create_table "attempts", force: :cascade do |t|
    t.boolean "correct", default: false, null: false
    t.datetime "created_at", null: false
    t.string "from_language", null: false
    t.string "given"
    t.integer "term_id", null: false
    t.string "to_language", null: false
    t.datetime "updated_at", null: false
    t.index ["from_language", "to_language", "term_id"], name: "index_attempts_on_from_language_and_to_language_and_term_id"
    t.index ["term_id"], name: "index_attempts_on_term_id"
  end

  create_table "decks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_decks_on_slug", unique: true
  end

  create_table "terms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "deck_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["deck_id"], name: "index_terms_on_deck_id"
  end

  create_table "translations", force: :cascade do |t|
    t.string "alternates"
    t.string "article"
    t.datetime "created_at", null: false
    t.string "language", null: false
    t.integer "term_id", null: false
    t.string "text", null: false
    t.datetime "updated_at", null: false
    t.index ["term_id", "language"], name: "index_translations_on_term_id_and_language", unique: true
    t.index ["term_id"], name: "index_translations_on_term_id"
  end

  add_foreign_key "attempts", "terms"
  add_foreign_key "terms", "decks"
  add_foreign_key "translations", "terms"
end
