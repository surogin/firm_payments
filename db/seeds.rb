# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

Firm.upsert_all([
  { id: 1, name: "Pinecrest CPA Group", balance_cents: 5_000_000, uuid: "3f1c9a2e-7b4d-4c1e-9a55-2d8e6f0b7c41" },
  { id: 2, name: "Lopez Bookkeeping", balance_cents: 50_000, uuid: "8b2e4c71-0d3a-4f6e-b1c9-5a7d2e9f4c10" },
  { id: 3, name: "Nair Tax Services", balance_cents: 200_000, uuid: "e5f18b3c-2a9d-4c07-8e6b-1d4a7f9c3b25" }
])
ActiveRecord::Base.connection.reset_pk_sequence!(Firm.table_name)
