# frozen_string_literal: true

every :day, at: "03:00am" do
  runner "Hoge.run"
end

every "0 0 1 * *" do
  rake "hoge:run"
  runner "Fuga.run"
end
