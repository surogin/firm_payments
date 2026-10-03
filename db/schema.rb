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

ActiveRecord::Schema[8.1].define(version: 2026_10_03_050803) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "firms", force: :cascade do |t|
    t.text "name", null: false
    t.bigint "balance_cents", default: 0, null: false
    t.text "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["uuid"], name: "index_firms_on_uuid", unique: true
    t.check_constraint "balance_cents >= 0", name: "firms_balance_non_negative"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "payer_firm_id", null: false
    t.bigint "payee_firm_id", null: false
    t.bigint "amount_cents", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["payee_firm_id"], name: "index_payments_on_payee_firm_id"
    t.index ["payer_firm_id"], name: "index_payments_on_payer_firm_id"
    t.check_constraint "amount_cents > 0", name: "payments_amount_positive"
  end

  add_foreign_key "payments", "firms", column: "payee_firm_id"
  add_foreign_key "payments", "firms", column: "payer_firm_id"
end
