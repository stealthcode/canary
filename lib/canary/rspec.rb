require 'rspec/core/formatters/base_formatter'
require 'uri'
require 'net/http'
require 'socket'
require 'mongo'
require_relative 'domain'
require_relative 'exec'
require_relative 'script'

module Canary::RSpec
  class StoryManager < ::RSpec::Core::Formatters::BaseFormatter
    attr_accessor :test_suite
    def initialize(output)
      super(output)
      @test_suite = Canary.active_suite
    end

    def start(count)
      @test_suite.start(count)
      if Canary.config['CaptureVersion']
        @test_suite.versions = Canary.find_system_versions
      end

      # Catches the process when it is ended prematurely and calls #stop
      # This does not work running on windows when using the RubyMine process runner
      # see http://youtrack.jetbrains.com/issue/RUBY-11492
      at_exit { stop }
    end

    def stop
      if @finished.nil?
        @finished = true
        @test_suite.complete
      end
    end

    def example_group_started(eg)
      category = eg.metadata[:description]
      file = eg.metadata[:file_path]
      line = eg.metadata[:line_number]
      nest_depth = nested_level(eg.metadata[:example_group], 0)
      @test_suite.start_group(category, file, line, nest_depth)
    end

    def example_started(example)
      super
      category_id = Canary.add_category(example)

      @test_suite.add_new_story(
          category_id,
          example.metadata[:description],
          example.metadata[:file_path],
          example.metadata[:line_number])
      raise 'Cannot use the key "test_id" as an example group description' if Canary.categories.has_key?('test_id')
    end

    def example_passed(example)
      super(example)
      message = example.metadata[:execution_result][:status]
      run_time = example.metadata[:execution_result][:run_time]
      @test_suite.example_passed(message, run_time)
    end

    def example_failed(example)
      super(example)
      message = example.metadata[:execution_result][:exception].message
      run_time = example.metadata[:execution_result][:run_time]
      exception = example.metadata[:execution_result][:exception]
      @test_suite.example_failed(message, exception, run_time)
    end

    private
    def nested_level(metadata, lvl)
      if metadata.has_key?(:example_group)
        lvl = nested_level(metadata[:example_group], lvl + 1)
      end
      lvl
    end
  end

  class ConsoleReporter < ::RSpec::Core::Formatters::BaseFormatter

    def initialize(args)
      super
      @last_category_id = -1
    end

    def example_passed(example)
      super
      print_category(example)
      puts " P (#{Canary.active_story.description}) -> #{Canary.active_story.message}"
    end

    def print_category(example)
      if @last_category_id != Canary.active_story.category
        puts "#{Canary.list_of_nested_groups(example).join(' < ')}"
        @last_category_id = Canary.active_story.category
      end
    end

    def example_failed(example)
      super
      print_category(example)
      puts " F (#{Canary.active_story.description}) -> #{Canary.active_story.message}"
    end

    def stop
      failing_tests = Canary.story_list.map { |test| test if test.failed? }.select { |t| !t.nil?}
      puts "Failures: #{failing_tests.count}" if failing_tests.count > 0
      puts "Failing Tests" if failing_tests.count > 0
      print_test(failing_tests)
    end

    def print_test(failing_tests)
      story_features = Set.new
      failing_tests.each { |test|
        story = test.story
        puts "failing story         #{test.category} (#{test.description})"
        i = 1
        story.task_history.each {|step|
          step.actions.each {|action|
            msg  = "  task # #{i}             #{action.metadata[:method]} "
            msg += "#{action.metadata[:args]}" if action.metadata[:args].count > 0
            puts msg
            i += 1
            action.log.each {|step|
              action_features = step[:features].to_a.map {|f| "<#{f}>"}.join ', '
              puts "                       #{step[:description]} #{action_features}"
              story_features.merge(step[:features])
            }
          }
        }
        puts "  failure message      #{test.message}"
        puts "  all features(s)      #{story_features.to_a.map {|f| "<#{f}>"}.join ', '}"
      }
    end
  end
end
