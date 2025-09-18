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

ActiveRecord::Schema[7.2].define(version: 2025_09_18_152938) do
  create_table "admins", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
  end

  create_table "attendances", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "member_id", null: false
    t.integer "status", default: 0, null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "member_id"], name: "index_attendances_on_event_id_and_member_id", unique: true
    t.index ["event_id"], name: "index_attendances_on_event_id"
    t.index ["member_id"], name: "index_attendances_on_member_id"
    t.index ["status"], name: "index_attendances_on_status"
  end

  create_table "event_participants", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "member_id", null: false
    t.integer "status", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "member_id"], name: "index_event_participants_on_event_id_and_member_id", unique: true
    t.index ["event_id"], name: "index_event_participants_on_event_id"
    t.index ["member_id"], name: "index_event_participants_on_member_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "title", null: false
    t.date "date", null: false
    t.integer "court_count", default: 2, null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["date"], name: "index_events_on_date"
    t.index ["status"], name: "index_events_on_status"
  end

  create_table "matches", force: :cascade do |t|
    t.integer "round_id", null: false
    t.integer "court_number", null: false
    t.integer "pair1_member1_id"
    t.integer "pair1_member2_id"
    t.integer "pair2_member1_id"
    t.integer "pair2_member2_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pair1_member1_id"], name: "index_matches_on_pair1_member1_id"
    t.index ["pair1_member2_id"], name: "index_matches_on_pair1_member2_id"
    t.index ["pair2_member1_id"], name: "index_matches_on_pair2_member1_id"
    t.index ["pair2_member2_id"], name: "index_matches_on_pair2_member2_id"
    t.index ["round_id", "court_number"], name: "index_matches_on_round_id_and_court_number", unique: true
    t.index ["round_id"], name: "index_matches_on_round_id"
  end

  create_table "member_relations", force: :cascade do |t|
    t.integer "member_id", null: false
    t.integer "other_member_id", null: false
    t.integer "kind", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id", "other_member_id", "kind"], name: "idx_member_relations_unique", unique: true
    t.index ["member_id"], name: "index_member_relations_on_member_id"
    t.index ["other_member_id", "member_id", "kind"], name: "idx_member_relations_unique_rev", unique: true
    t.index ["other_member_id"], name: "index_member_relations_on_other_member_id"
  end

  create_table "members", force: :cascade do |t|
    t.string "name", null: false
    t.integer "grade", null: false
    t.integer "skill_level", default: 0, null: false
    t.integer "gender", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "level", default: 0, null: false
    t.string "name_kana"
    t.index ["active"], name: "index_members_on_active"
    t.index ["gender"], name: "index_members_on_gender"
    t.index ["level"], name: "index_members_on_level"
    t.index ["name"], name: "index_members_on_name"
    t.index ["skill_level"], name: "index_members_on_skill_level"
  end

  create_table "rounds", force: :cascade do |t|
    t.integer "event_id", null: false
    t.integer "index", null: false
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "index"], name: "index_rounds_on_event_id_and_index", unique: true
    t.index ["event_id"], name: "index_rounds_on_event_id"
  end

  add_foreign_key "attendances", "events"
  add_foreign_key "attendances", "members"
  add_foreign_key "event_participants", "events"
  add_foreign_key "event_participants", "members"
  add_foreign_key "matches", "members", column: "pair1_member1_id"
  add_foreign_key "matches", "members", column: "pair1_member2_id"
  add_foreign_key "matches", "members", column: "pair2_member1_id"
  add_foreign_key "matches", "members", column: "pair2_member2_id"
  add_foreign_key "matches", "rounds"
  add_foreign_key "rounds", "events"
end
