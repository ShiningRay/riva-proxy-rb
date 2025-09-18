require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# Default task
task default: [:spec, :rubocop]

# RSpec tasks
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.exclude_pattern = 'spec/integration/**/*_spec.rb'
end

RSpec::Core::RakeTask.new(:spec_integration) do |t|
  t.pattern = 'spec/integration/**/*_spec.rb'
end

RSpec::Core::RakeTask.new(:spec_all) do |t|
  t.pattern = 'spec/**/*_spec.rb'
end

# RuboCop task
RuboCop::RakeTask.new

# Custom tasks
desc 'Generate protobuf code from .proto files'
task :generate_proto do
  sh 'bundle exec grpc_tools_ruby_protoc -I . --ruby_out=lib/riva_proxy/proto --grpc_out=lib/riva_proxy/proto riva_asr.proto'
  puts 'Protobuf code generated successfully!'
end

desc 'Start mock server'
task :server do
  port = ENV['PORT'] || 50051
  puts "Starting mock server on port #{port}"
  sh "ruby bin/mock_server #{port}"
end

desc 'Run client example'
task :example do
  sh 'ruby examples/client_example.rb'
end

desc 'Clean generated files'
task :clean do
  FileUtils.rm_rf('lib/riva_proxy/proto')
  FileUtils.mkdir_p('lib/riva_proxy/proto')
  puts 'Cleaned generated protobuf files'
end

desc 'Setup project (install dependencies and generate protobuf code)'
task :setup do
  sh 'bundle install'
  Rake::Task[:generate_proto].invoke
  puts 'Project setup complete!'
end

desc 'Run all tests including integration tests'
task :test_all do
  Rake::Task[:spec_all].invoke
end

desc 'Check code quality'
task :quality do
  Rake::Task[:rubocop].invoke
  Rake::Task[:spec].invoke
end