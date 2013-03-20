require 'rspec'

module Canary
    class << self
        attr_accessor :test_name
        def run(spec, name, examples)
            # need to set the test name here instead of in the custom formatter
            Canary.test_name = name 
            puts "running: " + name
            examples.each { |example| 
                args = [spec, '-e', example]
                puts "args: #{args}"
                ::RSpec::Core::Runner.run(args) 
            }
        end
    end
end