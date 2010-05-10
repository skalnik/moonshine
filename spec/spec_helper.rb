require 'rubygems'
require 'spec/autorun'

require 'ginger'

require 'moonshine'
require 'shadow_puppet/test'
require 'mocha'

# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

Spec::Runner.configure do |config|
  config.include MoonshineHelpers
  config.extend MoonshineHelpers::ClassMethods
end

