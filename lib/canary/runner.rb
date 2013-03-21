require 'rspec'
require 'rspec/core/configuration_options'
require 'rspec/core/command_line'

module Canary
    class << self
        attr_accessor :test_name
        def run(spec, name, examples)
            # need to set the test name here instead of in the custom formatter
            Canary.test_name = name 
            puts "running: " + name
            args = [spec] + examples.map { |example| ['-e', example]}.flatten
            puts "args = #{args}"
            rspec_it(args) 
        end

        def rspec_it(args, err=$stderr, out=$stdout) 
            ::RSpec::Core::Runner.trap_interrupt
            ::RSpec::Core::CommandLine.new(args).run(err, out)
        end
    end
end