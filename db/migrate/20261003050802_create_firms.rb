class CreateFirms < ActiveRecord::Migration[8.1]
  def change
    create_table :firms do |t|
      t.text :name, null: false
      t.bigint :balance_cents, null: false, default: 0
      t.text :uuid, null: false, default: -> { "gen_random_uuid()" }

      t.timestamps

      t.index :uuid, unique: true
      t.check_constraint "balance_cents >= 0", name: "firms_balance_non_negative"
    end
  end
end
