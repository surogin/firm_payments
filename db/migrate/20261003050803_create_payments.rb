class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    create_table :payments do |t|
      t.references :payer_firm, null: false, foreign_key: { to_table: :firms }
      t.references :payee_firm, null: false, foreign_key: { to_table: :firms }
      t.bigint :amount_cents, null: false
      t.text :description

      t.timestamps

      t.check_constraint "amount_cents > 0", name: "payments_amount_positive"
    end
  end
end
