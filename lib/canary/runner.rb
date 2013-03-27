require 'rspec'
require 'rspec/core/configuration_options'
require 'rspec/core/command_line'

module Canary
    class << self
        attr_accessor :test_name
        def run(spec, test_suites)
            test_suites.each { |suite| 
                Canary.run_test_suite(suite)
                suite.each { |test|
                    test_name = test['name']
                    examples = test['examples']
                    args = [spec] + examples.map{ |example| ['-e', example]}.flatten
                    puts "running: " + test_name
                    puts "args = #{args}"
                    rspec_it(args)
                    
                }
                Canary.end_test_suite
            } 
            # need to set the test name here instead of in the custom formatter
        end

        def rspec_it(args, err=$stderr, out=$stdout) 
            ::RSpec::Core::Runner.trap_interrupt
            ::RSpec::Core::CommandLine.new(args).run(err, out)
        end
    end
end