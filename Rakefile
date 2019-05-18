require "bundler"
Bundler::GemHelper.install_tasks

require "rake/testtask"

import 'lib/tasks/helix_runtime.rake'

Rake::TestTask.new(:test) do |t|
  t.libs.push("lib", "test")
  t.test_files = FileList["test/**/test_*.rb"]
  t.verbose = true
  t.warning = true
end

task default: [:test]
