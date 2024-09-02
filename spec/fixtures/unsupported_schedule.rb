# frozen_string_literal: true

job_type :awesome, "/usr/local/bin/awesome :task :fun_level"

every :reboot do
  rake "hoge:run"
end
