class Users < Canary::Data::SQLData
  def initialize
    super(:user_sql)
    @sql = <<-EOSQL
SELECT
  [user_id],
  [username],
  [start_date],
  [end_date],
  [create_date]
FROM [User_Accounts]
WHERE [user_id] = $$$ID$$$
    EOSQL
  end
end